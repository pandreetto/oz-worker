# coding=utf-8
"""Author: Lukasz Opiola
Copyright (C) 2015 ACK CYFRONET AGH
This software is released under the MIT license cited in 'LICENSE.txt'

Utility module to handle livereload of Ember GUI (for development purposes) on
dockers.
"""

import os
import re
from . import common, docker


def required_volumes(gui_config_file, project_src_dir, docker_src_dir):
    """
    Returns volumes that are required for livereload to work based on:
    project_src_dir - path on host to project root
    docker_src_dir - path on docker to project root
    gui_src_dir - path to gui sources relative to project root
    """
    source_gui_dir = _parse_erl_config(gui_config_file, 'source_gui_dir')
    return [
        (
            os.path.join(project_src_dir, source_gui_dir),
            os.path.join(docker_src_dir, source_gui_dir),
            'rw'
        )
    ]


def run(container_id, gui_config_file, docker_src_dir, docker_bin_dir,
        mode='watch'):
    """
    Runs automatic rebuilding of project and livereload of web pages when
    their code changes.
    mode can be:
        'watch' - use FS watcher, does not work on network filesystems
        'poll' - poll for changes, slower but works everywhere
    """
    watch_changes(container_id, gui_config_file, docker_src_dir, docker_bin_dir,
                  mode=mode)
    start_livereload(container_id, gui_config_file, docker_bin_dir, mode=mode)


def watch_changes(container_id, gui_config_file, docker_src_dir,
                  docker_bin_dir, mode='watch', detach=True):
    """
    Starts a process on given docker that monitors changes in GUI sources and
    rebuilds the project when something changes.
    mode can be:
        'watch' - use FS watcher, does not work on network filesystems
        'poll' - poll for changes, slower but works everywhere
    """
    source_gui_dir = _parse_erl_config(gui_config_file, 'source_gui_dir')
    source_gui_dir = os.path.join(docker_src_dir, source_gui_dir)
    source_tmp_dir = os.path.join(source_gui_dir, 'tmp')
    release_gui_dir = _parse_erl_config(gui_config_file, 'release_gui_dir')
    release_gui_dir = os.path.join(docker_bin_dir, release_gui_dir)

    watch_option = '--watch'
    if mode == 'poll':
        watch_option = '--watch --watcher=polling'

    # Start a process that will chown ember tmp dir
    # (so that it does not belong to root afterwards)
    command = '''\
mkdir -p /root/bin/
mkdir -p {source_tmp_dir}
chown -R {uid}:{gid} {source_tmp_dir}
echo 'while ((1)); do chown -R {uid}:{gid} {source_tmp_dir}; sleep 1; done' > /root/bin/chown_tmp_dir.sh
chmod +x /root/bin/chown_tmp_dir.sh
nohup bash /root/bin/chown_tmp_dir.sh &
cd {source_gui_dir}
ember build {watch_option} --output-path={release_gui_dir} | tee /tmp/ember_build.log'''
    command = command.format(
        uid=os.geteuid(),
        gid=os.getegid(),
        source_tmp_dir=source_tmp_dir,
        source_gui_dir=source_gui_dir,
        watch_option=watch_option,
        release_gui_dir=release_gui_dir)

    docker.exec_(
        container=container_id,
        detach=detach,
        interactive=True,
        tty=True,
        command=command)


def start_livereload(container_id, gui_config_file,
                     docker_bin_dir, mode='watch', detach=True):
    """
    Starts a process on given docker that monitors changes in GUI release and
    forces a page reload using websocket connection to client. The WS connection
    is created when livereload script is injected on the page - this must be
    done from the Ember client app.
    mode can be:
        'watch' - use FS watcher, does not work on network filesystems
        'poll' - poll for changes, slower but works everywhere
    """
    release_gui_dir = _parse_erl_config(gui_config_file, 'release_gui_dir')
    release_gui_dir = os.path.join(docker_bin_dir, release_gui_dir)

    watch_option = 'watch'
    if mode == 'poll':
        watch_option = 'poll'

    # Copy the js script that start livereload and a cert that will
    # allow to start a https server for livereload
    command = '''\
cat <<"EOF" > /tmp/gui_livereload_cert.pem
{gui_livereload_cert}
EOF
cd {release_gui_dir}
npm link livereload
cat <<"EOF" > gui_livereload.js
{gui_livereload}
EOF
node gui_livereload.js . {watch_option} /tmp/gui_livereload_cert.pem'''
    js_path = os.path.join(common.get_script_dir(), 'gui_livereload.js')
    cert_path = os.path.join(common.get_script_dir(), 'gui_livereload_cert.pem')
    command = command.format(
        release_gui_dir=release_gui_dir,
        gui_livereload_cert=open(cert_path, 'r').read(),
        gui_livereload=open(js_path, 'r').read(),
        watch_option=watch_option)

    docker.exec_(
        container=container_id,
        detach=detach,
        interactive=True,
        tty=True,
        command=command,
        output=True)


def _parse_erl_config(file, param_name):
    """
    Parses an erlang-style config file finding a tuple by key and extracting
    the value. The tuple must be in form {key, "value"} (and in one line).
    """
    file = open(file, 'r')
    file_content = file.read()
    file.close()
    matches = re.findall("{" + param_name + ".*", file_content)
    return matches[0].split('"')[1]
