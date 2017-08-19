require! './src/actor': {Actor}
require! './src/io-actor': {IoActor}
require! './src/socketio-browser': {SocketIOBrowser}
require! './src/signal': {Signal}
require! './src/find-actor': {find-actor}
require! './src/couch-proxy': {CouchProxy}
require! './src/topic-match': {topic-match}

module.exports = {
    IoActor, SocketIOBrowser, Signal, Actor
    find-actor, CouchProxy
    topic-match
}
