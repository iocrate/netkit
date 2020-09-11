## This module contains miscellaneous functions that don’t really belong in any other module.

template offset*(p: pointer, n: int): pointer = 
  ## 返回一个新的指针，该指针从 ``p`` 向后偏移 ``n`` 个字节。
  cast[pointer](cast[ByteAddress](p) + n)

template checkDefNatural*(value: static[Natural], name: static[string]): untyped = 
  ## Checks whether ``value`` is a natural number (zero and positive integer). If not, then stop compiling. ``name`` 
  ## specifies its symbolic name.
  when value < 0:
    {.fatal: "The value of '" & name & "' by ``--define`` must be greater than or equal to 0!".}