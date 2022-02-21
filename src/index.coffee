Object.assign exports,
  register: require './register'
  CoverageInstrumentor: require('./coffeeCoverage').CoverageInstrumentor
  findIstanbulVariable: require('./instrumentors/Istanbul').findIstanbulVariable
  version: require("../package.json").version
