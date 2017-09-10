require! 'uuid4'
require! 'aea': {sleep, logger, debug-levels, merge, EventEmitter}
require! 'prelude-ls': {empty}


export class ActorBase extends EventEmitter
    (@name) ->
        super!
        @id = uuid4!
        @name = @name or @id
        @log = new logger @name
        @msg-seq = 0

    msg-template: (msg) ->
        msg-raw =
            sender: null
            timestamp: Date.now! / 1000
            msg_id: @msg-seq++
            token: null

        if msg
            return msg-raw <<<< msg
        else
            return msg-raw
