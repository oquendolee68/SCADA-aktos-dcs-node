require! 'serialport': SerialPort
require! '../../lib': {pack, sleep, clone, EventEmitter, Logger}
require! '../../src/signal': {Signal}

export class SerialPortTransport extends EventEmitter
    (opts) ->
        '''
        Options: 

                opts =
                    # SerialPort options: https://serialport.io/docs/en/api-stream#openoptions
                    port: '/dev/ttyUSB0' or 'COM1'
                    baudrate: 9600...
                    dataBits: 8  
                    stopBits: 1 
                    parity: 'even' # or 'none' or 'odd'

                    # This class' options
                    split-at: null # null for raw reading. Possible options: '\n'
        '''
        default-opts =
            baudrate: 9600baud
            split-at: null  # string or function (useful for binary protocols)

        opts = default-opts <<< opts
        throw 'Port is required' unless opts.port
        super!

        @log = new Logger "Serial #{opts.port}"
        @reconnect-timeout = new Signal
        @_reconnecting = no
        @on \do-reconnect, ~>
            if @_reconnecting
                return @log.warn "Already trying to reconnect"
            @_reconnecting = yes

            recv = ''
            #@log.log "opening port..."
            ser-opts = clone opts 
            delete ser-opts.split-at
            ser-opts.baudRate = ser-opts.baudrate
            delete ser-opts.baudrate

            @reconnect-timeout.wait 1000ms, (err, opening-err) ~>
                if err or opening-err
                    <~ sleep 1000ms
                    @ser = null
                    @trigger \do-reconnect

            unless @ser
                @ser = new SerialPort opts.port, ser-opts, (err) ~>
                    #console.log "initializing ser:", err
                    @reconnect-timeout.go err
                    unless err
                        @connected = yes

                #console.log "serial port is:", @ser

            @ser
                ..on \error, (e) ~>
                    @log.warn "Error while opening port: ", pack e
                    @ser = null
                    <~ sleep 1000ms
                    @_reconnecting = no
                    @trigger \do-reconnect

                ..on \open, ~>
                    @connected = yes

                ..on \data, (data) ~>
                    unless opts.split-at
                        @trigger \data, data
                    else
                        recv += data.to-string!
                        #@log.log "data is: ", recv
                        if recv.index-of(opts.split-at) > -1
                            @trigger \data, recv
                            recv := ''

                ..on \close, (e) ~>
                    #@log.log "something went wrong with the serial port...", e
                    @connected = no
                    <~ sleep 1000ms
                    @_reconnecting = no
                    @trigger \do-reconnect
            @_reconnecting = no
        @trigger \do-reconnect

    connected: ~
        ->
            @_connected
        (val) ->
            @_connected = val
            if not @_connected0 and @_connected
                @trigger \connect

            if @_connected0 and not @_connected 
                @trigger \disconnect

            @_connected0 = @_connected

    write: (data, callback) ->
        if @connected
            #@log.log "writing data..."
            @ser.write data, ~>
                #@log.log "written data"
                callback? err=no
        else
            #@log.warn "not connected, not writing."
            callback? do
                message: 'not connected'

if require.main is module
    # do short circuit Rx and Tx pins
    logger = new Logger 'APP'
    port = new SerialPortTransport {
        baudrate: 9600baud
        port: '/dev/ttyUSB0'
        split-at: '\n'
        }
        ..on \connect, ->
            logger.log "app says serial port is connected"

        ..on \data, (frame) ~>
            logger.log "frame received:", frame

        ..on \disconnect, ~>
            logger.log "app says disconnected "

    <~ port.once \connect
    <~ :lo(op) ~>
        logger.log "sending \"something * 5\"..."
        err <~ port.write ('something' * 5) + '\n'
        if err
            logger.err "something went wrong while writing: ", err
            <~ port.once \connect
            logger.log "error is resolved, continuing"
            lo(op)
        else
            <~ sleep 2000ms
            lo(op)
