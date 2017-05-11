#!/bin/sh
# uploads a file to test.txt with the credentials of user 1234
curl -X PUT http://localhost:2048/1234/test.txt?user=1234\&key=1234567654321 -d 'hello world!'
