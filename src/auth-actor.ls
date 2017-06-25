require! './actor': {Actor}
require! 'prelude-ls': {find}
require! './signal': {Signal}
require! 'aea': {sleep, clone}

class LocalStorage
    (@name) ->
        @s = local-storage

    set: (key, value) ->
        @s.set-item key, value

    del: (key) ->
        @s.remove-item key

    get: (key) ->
        @s.get-item key


# AuthActor can interact with SocketIOBrowser
export class AuthActor extends Actor
    @instance = null
    ->
        return @@instance if @@instance
        @@instance = this

        super 'AuthActor'
        @db = new LocalStorage \auth

    post-init: ->
        @login-signal = Signal!
        @logout-signal = Signal!
        @check-signal = Signal!
        @checking = no
        @checked-already = no

        <~ :lo(op) ~>
            @io-actor = find (.name is \SocketIOBrowser), @mgr.actor-list
            return op! if @io-actor
            @log.log "io actor is not found, checking again after 100ms"
            <~ sleep 20ms
            lo(op)

        @io-actor.on 'network-receive', (msg) ~>
            if \auth of msg
                #@log.log "Auth actor got authentication message", msg
                if \session of msg.auth
                    #@login-signal.go msg
                    void
                else if \logout of msg.auth
                    if msg.auth.logout is \ok
                        @logout-signal.go msg

                @check-signal.go msg

    login: (ctx, credentials, callback) ->
        @send-to-remote auth: credentials
        # FIXME: why do we need to clear the signal?
        @login-signal.clear!
        __ = @
        reason, res <~ @login-signal.wait ctx, 300ms

        reason = \hello
        res =
            auth: session: \bad
        err = if reason is \timeout
            {reason: \timeout}
        else
            no

        # set socketio-browser's token variable in order to use it in every message
        __.io-actor.token = try res.auth.session.token

        __.db.set \token, __.io-actor.token
        callback.call ctx, err, res


    logout: (callback) ->
        @send-to-remote auth: logout: yes
        reason, msg <~ @logout-signal.wait 3000ms
        err = if reason is \timeout
            {reason: 'timeout'}
        else
            no

        if not err and msg.auth.logout is \ok
            @log.log "clearing local storage"
            @db.del \token

        callback err, msg

    check-session: (callback) ->
        if @checking
            callback {code: 'singleton', reason: 'checking already'}
            @log.log "checking already..."
            return

        if @checked-already
            callback {code: 'already-checked', reason: 'session already checked'}
            return

        @checking = yes
        token = @db.get \token
        @send-to-remote auth: token: token
        reason, msg <~ @check-signal.wait 5000ms
        #@db.del \token
        @log.log "server responded check-session with: ", msg
        err = if reason is \timeout
            {reason: 'server not responded in a reasonable amount of time'}
        else
            no

        try
            if msg
                @io-actor.token = msg.auth.session.token
            else
                @log.warn "Why is this signal triggered if there is no msg? msg: ", msg
        catch
            err = {reason: e}

        @checking = no
        @checked-already = yes
        callback err, msg

    send-to-remote: (msg) ->
        <~ :lo(op) ~>
            if @io-actor
                msg.sender = @actor-id
                enveloped-message = @io-actor.msg-template msg
                @io-actor.network-send-raw enveloped-message
                return
            else
                @log.warn "tried to send following message before socketio browser is ready:", msg
                <~ sleep 10ms
                lo(op)
