module NoPain
  module Data
    module Filters
      # Regexp filters
      ID=/\A[a-fA-F0-9]{24}\z/
      MAC=/\A([a-fA-F0-9]{2}:){5}[a-fA-F0-9]{2}\z/
      PACKAGEROOT=/\A[a-zA-Z0-9:_&\/.%\z-]+\z/
      KERNEL=/\A[a-zA-Z0-9._-]+\z/
      FILENAME=/\A[a-zA-Z0-9._\/-]+\z/
      DIRNAME=/\A[a-zA-Z0-9._-]+\z/
      HOSTNAME=/\A[a-zA-Z0-9.-]+\z/
      NAME=/\A[a-zA-Z0-9. _-]+\z/
      RAID=/\A[a-zA-Z0-9]+\z/
      DOMAIN=/\A([a-zA-Z0-9]+\.?)+[a-zA-Z]+\z/
      REQUEST_TYPE=/\A(discover)|(request)|(none)\z/
      INTERNAL_FIELD=/(\A_)|(_id\z)/
      NETWORK_NAME=/\A[a-zA-Z0-9. \(\)_\/-]+\z/
      UUID=/\A[a-z0-9]{8}-([a-z0-9]{4}-){3}[a-z0-9]{12}\z/
      IP=/\A(((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))\.){3}((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))\z/
      NETWORK=/\A(((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))\.){3}((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))\/(([8,9])|([1,2][0-9])|(3[0-2]))\z/
      EXCEPTIONS=/\A((((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))\.){3}((2?5?[0-5])|(2?[0-4]?[0-9])|([01]?[0-9]{2}?))|,)*\z/
      NETMASK=/\A([89])|([12][0-9])|(3[0-2])\z/
      VLAN=/\A([0-9]{1,4})|(none)\z/
    end
  end
end
