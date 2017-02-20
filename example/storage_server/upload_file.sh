#!/bin/sh
# uploads a file to test.txt with the credentials of user 1234
curl -X PUT http://localhost:2048/test.txt?user=1234 -d 'hello world!'
