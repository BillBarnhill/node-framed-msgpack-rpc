
fs = require 'fs'
path = require 'path'
colors = require 'colors'
deep_equal = require 'deep-equal'
{Logger,RobustTransport,Transport,Client} = require '../src/main'

argv = require('optimist').usage('Usage: $0 [-d]').argv

CHECK = "\u2714"
FUUUU = "\u2716"
ARROW = "\u2192"

##-----------------------------------------------------------------------

class VerboseTestLogger extends Logger
  
  @my_ohook : (m) -> console.log " #{ARROW} #{m}".yellow
  
  info : (m) -> @_log m, "I",  VerboseTestLogger.my_ohook
  warn : (m) -> @_log m, "W",  VerboseTestLogger.my_ohook
  error : (m) -> @_log m, "E", VerboseTestLogger.my_ohook

##-----------------------------------------------------------------------

class QuietTestLogger extends Logger

  _log : () -> null

##-----------------------------------------------------------------------

class GlobalTester
  logger : () ->
    klass = if argv.d then VerboseTestLogger else QuietTestLogger
    new klass {}

  connect : (port, prog, cb, rtopts) ->
    opts = { port, host : "-" }
    klass = if rtopts then RobustTransport else Transport
    x = new klass opts, rtopts
    await x.connect defer ok
    if not ok
      @error "Failed to connect in TcpTransport..."
      x = null
    else
      c = new Client x, prog
    cb x, c

##-----------------------------------------------------------------------

class TestCase
  constructor : (@_global) ->
    @_ok = true

  logger : () -> @_global.logger()
    
  search : (s, re, msg) ->
    @assert (s? and s.search(re) >= 0), msg

  assert : (f, what) ->
    if not f
      console.log "Assertion failed: #{what}"
      @_ok = false

  equal : (a,b,what) ->
    if not deep_equal a, b
      console.log "In #{what}: #{JSON.stringify a} != #{JSON.stringify b}".red
      @_ok = false

  test_rpc : (cli, method, arg, expected, cb) ->
    full = [ cli.program , method ].join "."
    await cli.invoke method, arg, defer error, result
    @check_rpc full, error, result, expected
    cb()

  error : (e) ->
    console.log e.red
    @_ok = false

  check_rpc: (name, error, result, expected) ->
    if error then @error "In #{name}: #{JSON.stringify error}"
    else @equal result, expected, "#{name} RPC result"

  is_ok : () -> @_ok

  connect : (port, prog, cb, rtopts) ->
    @_global.connect port, prog, cb, rtopts
   
##-----------------------------------------------------------------------

class Runner

  ##-----------------------------------------
  
  constructor : ->
    @_files = []
    @_launches = 0
    @_tests = 0
    @_successes = 0
    @_rc = 0
    @_n_files = 0
    @_n_good_files = 0
    @_global_tester = new GlobalTester

  ##-----------------------------------------
  
  err : (e) ->
    console.log e.red
    @_rc = -1

  ##-----------------------------------------
  
  load_files : (cb) ->
    @_dir = path.dirname __filename
    base = path.basename __filename
    await fs.readdir @_dir, defer err, files
    if err?
      ok = false
      @err "In reading #{@_dir}: #{err}"
    else
      ok = true
      re = /test.*\.(iced|coffee)$/
      for file in files when file.match(re) 
        @_files.push file
      @_files.sort()
    cb ok
  
  ##-----------------------------------------
  
  run_files : (cb) ->
    for f in @_files
      await @run_file f, defer()
    cb()

  ##-----------------------------------------

  create_tester : () -> new TestCase @_global_tester
   
  ##-----------------------------------------
  
  run_code : (f, code, cb) ->
    if code.init?
      await code.init defer(err), @_global_tester
    destroy = code.destroy
    delete code["init"]
    delete code["destroy"]
    @_n_files++
    if err
      @err "Failed to initialize file #{f}: #{err}"
    else
      @_n_good_files++
      for k,v of code
        @_tests++
        T = @create_tester()
        await v T, defer err
        if err
          @err "In #{f}/#{k}: #{err}"
        else if T.is_ok()
          @_successes++
          console.log "#{CHECK} #{f}: #{k}".green
        else
          console.log "#{FUUUU} #{f}: #{k}".bold.red
    await destroy defer(), @_global_tester if destroy
    cb()

  ##-----------------------------------------
  
  run_file : (f, cb) ->
    try
      dat = require path.join @_dir, f
      await @run_code f, dat, defer()
    catch e
      @err "In reading #{f}: #{e}\n#{e.stack}"
    cb()

  ##-----------------------------------------

  run : (cb) ->
    await @load_files defer ok
    await @run_files defer() if ok
    @report()
    cb @_rc
   
  ##-----------------------------------------

  report : () ->
    if @_rc < 0
      console.log "#{FUUUU} Failure due to test configuration issues".red
    @_rc = -1 unless @_tests is @_successes
    f = if @_rc is 0 then colors.green else colors.red
    
    console.log f "Tests: #{@_successes}/#{@_tests} passed".bold
    
    if @_n_files isnt @_n_good_files
      console.log (" -> Only #{@_n_good_files}/#{@_n_files}" + 
         " files ran properly").red.bold
    return @_rc
    
  ##-----------------------------------------
  
##-----------------------------------------------------------------------

runner = new Runner()
await runner.run defer rc
process.exit rc

##-----------------------------------------------------------------------
