#!/usr/bin/env bash
# Resy venue search – auth inlined for direct curl. Do not commit (see .gitignore).

curl -s -X POST 'https://api.resy.com/3/venuesearch/search' \
  -H 'Authorization: ResyAPI api_key="VbWk7s3L4KiK5fzlO7JD3Q5EYolJI7n5"' \
  -H 'x-resy-auth-token: eyJ0eXAiOiJKV1QiLCJhbGciOiJFUzI1NiJ9.eyJleHAiOjE3NzM2MTI5NTMsInVpZCI6MjYyOTc2MDIsImd0IjoiY29uc3VtZXIiLCJncyI6W10sImxhbmciOiJlbi11cyIsImV4dHJhIjp7Imd1ZXN0X2lkIjo5ODcwNzIwN319.AN-KChAjkNUJ7Lg0NdPLmi1kcZbhQihKIbgU2BT9gU1kQ8HhMQINmkCXbhVQGahvSEFWuJQVfh4RgCF2sj8_OA1VAZWjBiA-1b_gh8E6IkmNvT5vxg2e2fVKOFM0diVzZ5CnK9Gfjj7U52_d1mI2AFKyrNafygOaGPoNtRtZHiDEqs5U' \
  -H 'Origin: https://resy.com' \
  -H 'Referer: https://resy.com/' \
  -H 'Content-Type: application/json' \
  -d '{"availability":true,"page":1,"per_page":20,"slot_filter":{"day":"2026-02-15","party_size":2,"time_filter":"21:00"},"types":["venue"],"order_by":"availability","geo":{"bounding_box":[40.69104047168222,-74.029110393126,40.7662954166697,-73.97769781072854]},"query":""}'
