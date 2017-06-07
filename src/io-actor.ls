/*

IoActor is an actor that subscribes IoMessage messages

# usage:

    # create instance
    actor = new IoActor 'pin-name'

    # send something
    actor.send-val 'some value to send'

    # receive something
    actor.handle_IoMessage = (msg) ->
        message handler that is fired on receive of IoMessage

 */

require! './actor': {Actor}
require! './filters': {FpsExec}

export class IoActor extends Actor
    (pin-name) ->
        super name=pin-name

        unless pin-name
            @log.err "no pin_name supplied!"
            return
        @pin-name = pin-name
        @fps = new FpsExec!
        @subscriptions =
            "IoMessage.#{pin-name}"
            "ConnectionStatus"

        @log.section \vvv, "actor is created with the following name: ", @actor-name, "and ID: #{@actor-id}"

    handle_ConnectionStatus: (msg) ->
        @log.log "Not implemented, message: ", msg

    sync: (ractive-var, topic=null) ->
        __ = @
        topic = "IoMessage.#{@pin-name}" unless topic
        @subscribe topic

        unless @ractive
            @log.err "set ractive variable first!"
            return

        handle = @ractive.observe ractive-var, (_new) ->
            _obj = {}
            _obj[topic] = _new
            __.fps.exec __.send, _obj

        @receive = (msg) ->
            if topic of msg.payload
                # payload has this topic
                handle.silence!
                __.ractive.set ractive-var, msg.payload[topic]
                handle.resume!
