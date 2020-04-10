#            netkit 
#        (c) Copyright 2020 Wang Tong
#
#    See the file "LICENSE", included in this
#    distribution, for details about the copyright.

template checkDefNatural*(value: static[Natural], name: static[string]): untyped = 
  ## 
  when value < 0:
    {.fatal: "The value of '" & name & "' by ``--define`` must be greater than or equal to 0!".}