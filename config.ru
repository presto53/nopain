$LOAD_PATH << '.'
require 'puma'
require 'lib/api'

run NoPaIn::API
