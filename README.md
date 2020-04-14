Netkit [![Build Status](https://travis-ci.org/iocrate/netkit.svg?branch=master)](https://travis-ci.org/iocrate/netkit)
==========


As a versatile network development infrastructure, Netkit hopes to provide common tools for network programming. Netkit is out of the box, stable and safe. It includes most of the available network programming tools such as the basic client and server of TCP, UDP, HTTP, WebSocket, MQTT and some related tools.
Netkit is not intended to be a high-level productivity development tool, but as a reliable and efficient network infrastructure. Netkit consists of several sub modules, each of which provides some network tools.

**Now, Netkit is currently under active development.**

Test
---------

Run test: the package provides an automatic test script. Check config.nims for details. ``$Nim test < test file name > `` can test the specified file, such as ``$Nim test tbuffer`` will test the tests / tbuffer.nim file. ``$nimble test `` will test all test files in the tests directory.