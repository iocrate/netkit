Netkit 
==========

[![Build Status](https://travis-ci.org/iocrate/netkit.svg?branch=master)](https://travis-ci.org/iocrate/netkit)
[![Build Status](https://dev.azure.com/iocrate/netkit/_apis/build/status/iocrate.netkit?branchName=master)](https://dev.azure.com/iocrate/netkit/_build/latest?definitionId=1&branchName=master)

Netkit hopes to serve as a versatile network development kit, providing tools commonly used in network programming. Netkit should be out of the box, stable and secure. Netkit contains a number of commonly used network programming tools, such as TCP, UDP, TLS, HTTP, HTTPS, WebSocket and related utilities.

Netkit is not intended to be a high-level productivity development tool, ut rather a reliable and efficient network infrastructure. Netkit consists of several submodules, each of which provides some network tools.

**Now, Netkit is under active development.**

Test
---------

Run test: there is an automatic test script. Check config.nims for details. ``$ nim test <file_name> `` tests the specified file, for example, ``$ nim test tbuffer`` tests the file **tests/tbuffer.nim**. ``$ nimble test `` tests all test files in the **tests** directory.