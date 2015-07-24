// View that allows to select an access document by its refresh_token property.
// The record defining access document's structure can be found in dao_auth.hrl
function (doc) {
    if (doc.record__ == "access") {
        emit(doc.refresh_token, null)
    }
}