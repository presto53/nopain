$LOAD_PATH << '.'
require 'thin'
require 'lib/api'

run NoPaIn::API
