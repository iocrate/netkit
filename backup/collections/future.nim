
type
  Future* = object
    publish: proc ()
    subscribe: proc ()
    finished: bool
    # error*: ref Exception
    # value: T   
