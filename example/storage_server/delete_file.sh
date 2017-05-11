#!/bin/sh
# deletes a file using 5678's credentials
curl -X DELETE http://localhost:2048/1234/test.txt?user=1234\&key=1234567654321
