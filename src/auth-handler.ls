require! './actor-base': {ActorBase}
require! './signal': {Signal}
require! 'aea': {sleep, logger, pack}
require! './authorization':{get-all-permissions}
require! 'uuid4'
require! 'colors': {
    red, green, yellow,
    bg-red, bg-yellow, bg-green
    bg-cyan
}
require! 'aea/debug-log': {logger}
require! './auth-helpers': {hash-passwd}
require! './topic-match': {topic-match}

class SessionCache
    @cache = {}
    @instance = null
    ->
        return @@instance if @@instance
        @@instance = this
        @log = new logger \SessionCache
        @log.log green "SessionCache is initialized", pack @@cache

    add: (session) ->
        @log.log green "Adding session for #{session.user}", (yellow session.token)
        @@cache[session.token] = session

    get: (token) ->
        @@cache[token]

    drop: (token) ->
        @log.log yellow "Dropping session for user: #{@@cache[token].user} token: #{token}"
        delete @@cache[token]


export class AuthHandler extends ActorBase
    @login-delay = 10ms
    @i = 0
    (@db) ->
        super "AuthHandler.#{@@i++}"
        @session-cache = new SessionCache!

        unless @db
            @log.log bg-yellow "No db supplied, only public messages are allowed."

        @on \receive, (msg) ~>
            #@log.log "Processing authentication message"
            if @db
                if \user of msg.auth
                    # login request
                    err, doc <~ @db.get-user msg.auth.user
                    if err
                        @log.err "user \"#{msg.auth.user}\" is not found. err: ", pack err
                        @send auth: error: err
                    else
                        if doc.passwd-hash is msg.auth.password
                            err, permissions-db <~ @db.get-permissions
                            if err
                                @log.log "error while getting permissions"
                                # FIXME: send exception message to the client
                                return

                            token = uuid4!

                            session =
                                token: token
                                user: msg.auth.user
                                date: Date.now!
                                permissions: get-all-permissions doc.roles, permissions-db
                                opening-scene: doc.opening-scene

                            @session-cache.add session

                            @log.log bg-green "new Login: #{msg.auth.user} (#{token})"
                            @log.log "(...sending with #{@@login-delay}ms delay)"


                            @trigger \login, session.permissions
                            <~ sleep @@login-delay
                            @send auth: session: session
                        else
                            @log.err "wrong password", doc, msg.auth.password
                            @send auth: error: "wrong password"

                else if \logout of msg.auth
                    # session end request
                    unless @session-cache.get msg.token
                        @log.log bg-yellow "No user found with the following token: #{msg.token} "
                        @send auth:
                            logout: \ok
                            error: "no such user found"
                        @trigger \logout
                    else
                        @log.log "logging out for #{pack (@session-cache.get msg.token)}"
                        @session-cache.drop msg.token
                        @send auth:
                            logout: \ok
                        @trigger \logout

                else if \token of msg.auth
                    @log.log "Attempting to login with token: ", pack msg.auth
                    if (@session-cache.get msg.auth.token)?.token is msg.auth.token
                        # this is a valid session token
                        found-session = @session-cache.get(msg.auth.token)
                        @log.log bg-cyan "User \"#{found-session.user}\" has been logged in with token."
                        @trigger \login, found-session.permissions
                        <~ sleep @@login-delay
                        @send auth: session: found-session
                    else
                        # means "you are not already logged in, do a logout action over there"
                        @log.log bg-yellow "client doesn't seem to be logged in yet."
                        <~ sleep @@login-delay
                        @send auth: session: logout: 'yes'
                else
                    @log.err yellow "Can not determine which auth request this was: ", pack msg

            else
                @log.log "only public messages allowed, dropping auth messages"
                @send auth: error: 'NOTAUTHORITY'


    send: (msg) -> @send-raw @msg-template msg <<< sender: @id

    send-raw: (msg) ->
        ...

    filter-incoming: (msg) ->
        #@log.log yellow "filter-incoming: input: ", pack msg
        session = @session-cache.get msg.token
        if session?permissions
            msg.ctx = user: session.user
            for topic in session.permissions.rw
                if topic `topic-match` msg.topic
                    delete msg.token
                    return msg
        if msg.topic `topic-match` "public.**"
            delete msg.token
            return msg
        else
            @log.err bg-red "can not determine authorization."

        @log.err bg-red "filter-incoming dropping unauthorized message!"
        return
