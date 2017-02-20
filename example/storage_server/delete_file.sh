#!/bin/sh
# deletes a file using 5678's credentials
curl -X DELETE http://localhost:2048/test.txt?user=5678
