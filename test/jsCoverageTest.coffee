path                = require 'path'
{expect}            = require 'chai'
_                   = require 'lodash'
JSCoverage          = require '../src/instrumentors/JSCoverage'
coffeeCoverage      = require "../src/coffeeCoverage"

{COVERAGE_VAR, log} = require './testConfig'

FILENAME = "example.coffee"

pn = (pth) -> pth.split('/').join(path.sep)

checkLinesAreCovered = (code, lineNumbers, filename) ->
    normalizedFilename = filename.replace /\\/g, "\\\\"

    if !_.isArray(lineNumbers) then lineNumbers = [lineNumbers]
    lineNumbers.forEach (l) ->
        expect(code, "line #{l} should be instrumented")
        .to.contain "#{COVERAGE_VAR}[\"#{normalizedFilename}\"][#{l}]++;"

run = (source, options={}) ->
    filename = options.filename ? FILENAME
    coverageOptions = _.assign {log, coverageVar: COVERAGE_VAR}, options.coverageOptions
    instrumentor = new JSCoverage(filename, source, coverageOptions)
    result = coffeeCoverage._runInstrumentor instrumentor, filename, source, {log}

    if options.l
        checkLinesAreCovered result.js, options.l, instrumentor.shortFileName

    return {instrumentor, result}

describe "JSCoverage tests", ->
    it "should un-chain if statements", ->
        instrumentor = new coffeeCoverage.CoverageInstrumentor({
            coverageVar: COVERAGE_VAR
            log: log
        })
        source = """
            if x
                say "hello"
            else if y
                say "world"
            else
                say "!"
        """

        {init, js} = instrumentor.instrumentCoffee("example.coffee", source)
        code = js.replace(init, "")
        expect(code.trim()).to.equal '''
            (function() {
              _myCoverageVar["example.coffee"][1]++;

              if (x) {
                _myCoverageVar["example.coffee"][2]++;
                say("hello");
              } else {
                _myCoverageVar["example.coffee"][3]++;
                if (y) {
                  _myCoverageVar["example.coffee"][4]++;
                  say("world");
                } else {
                  _myCoverageVar["example.coffee"][6]++;
                  say("!");
                }
              }

            }).call(this);
        '''
        checkLinesAreCovered code, [1,2,3,4,6], "example.coffee"

    it "should generate abbreviated file names", ->
        {instrumentor, result} = run """
            say "hello world"
        """, {
            l: 1
            filename: '/foo/bar/baz/foo.coffee'
            coverageOptions: {
                basePath: '/foo'
                path: 'abbr'
            }
        }

        expect(instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee'

    it "should generate relative file names", ->
        {instrumentor, result} = run """
            say "hello world"
        """, {
            l: 1
            filename: '/foo/bar/baz/foo.coffee'
            coverageOptions: {
                basePath: '/foo'
                path: 'relative'
            }
        }

        expect(instrumentor.shortFileName).to.equal pn 'bar/baz/foo.coffee'

    it "should generate bare file names", ->
        {instrumentor, result} = run """
            say "hello world"
        """, {
            l: 1
            filename: '/foo/bar/baz/foo.coffee'
            coverageOptions: {
                basePath: '/foo'
            }
        }

        expect(instrumentor.shortFileName).to.equal 'foo.coffee'

    it "should generate unique file names (usedFileNames)", ->
        usedFileNames = []

        results = [
            '/foo/bar/baz/foo.coffee'
            '/foo/bar/bak/foo.coffee'
            '/foo/bar/bam/foo.coffee'
        ].map (filename) ->
            run """
                say "hello world"
            """, {
                l: 1
                filename,
                coverageOptions: {
                    usedFileNames,
                    basePath: '/foo',
                    path: 'abbr'
                }
            }

        expect(results[0].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee'
        expect(results[1].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee (1)'
        expect(results[2].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee (2)'


    it "should generate unique file names (usedFileNameMap)", ->
        usedFileNameMap = {}

        results = [
            '/foo/bar/baz/foo.coffee'
            '/foo/bar/bak/foo.coffee'
            '/foo/bar/bam/foo.coffee'
            '/foo/bar/baz/foo.coffee'
        ].map (filename) ->
            run """
                say "hello world"
            """, {
                l: 1
                filename,
                coverageOptions: {
                    usedFileNameMap: usedFileNameMap,
                    basePath: '/foo',
                    path: 'abbr'
                }
            }

        expect(results[0].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee'
        expect(results[1].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee (1)'
        expect(results[2].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee (2)'
        expect(results[3].instrumentor.shortFileName).to.equal pn 'b/b/foo.coffee'

    it "should never instrument the same line twice", ->
        {instrumentor, result} = run """
            if x then run("a") else run("b")
        """, {l: 1}

        {init, js} = result
        code = js.replace(init, "")

        # There should only be one occurance of coverage var.
        firstIndexOf = code.indexOf COVERAGE_VAR
        lastIndexOf = code.lastIndexOf COVERAGE_VAR
        expect(firstIndexOf).to.not.equal -1
        expect(firstIndexOf is lastIndexOf).to.be.true

    it "should not instrument statements with '!pragma coverage-skip-next' pragmas", ->
        {instrumentor, result} = run """
            console.log "hello"
            ### !pragma coverage-skip-next ###
            console.log "world"
            console.log "!"
        """, {l: [1, 4]}

        expect(result.js, "line 3 should not be instrumented")
        .to.not.contain "#{COVERAGE_VAR}[\"#{FILENAME}\"][3]++;"

    it "should not instrument statements with '!pragma no-coverage-next' pragmas", ->
        {instrumentor, result} = run """
            console.log "hello"
            ### !pragma no-coverage-next ###
            console.log "world"
            console.log "!"
        """, {l: [1, 4]}

        expect(result.js, "line 3 should not be instrumented")
        .to.not.contain "#{COVERAGE_VAR}[\"#{FILENAME}\"][3]++;"

    describe '_abbreviatedPath', ->
        testInstance = new JSCoverage("test.coffee", "")

        it 'should work for files', ->
            expect(testInstance._abbreviatedPath(pn 'foo/bar/baz.coffee')).to.equal pn 'f/b/baz.coffee'

        it 'should work for directories', ->
            expect(testInstance._abbreviatedPath(pn 'foo/bar/baz/')).to.equal pn 'f/b/baz/'

        it 'should work for absolute paths', ->
            expect(testInstance._abbreviatedPath(pn '/foo/bar/baz.coffee')).to.equal pn '/f/b/baz.coffee'

        it 'should work for paths containing "." and ".."', ->
            # Is this really desired behavior?
            expect(testInstance._abbreviatedPath(pn '/foo/bar/../qux/baz.coffee')).to.equal pn '/f/b/../q/baz.coffee'
            expect(testInstance._abbreviatedPath(pn '/foo/bar/./qux/baz.coffee')).to.equal pn '/f/b/./q/baz.coffee'

        it 'should work for unix-style hidden folders', ->
            expect(testInstance._abbreviatedPath(pn '/foo/bar/.bat/baz.coffee')).to.equal pn '/f/b/.b/baz.coffee'
