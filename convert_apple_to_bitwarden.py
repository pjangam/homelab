#!/usr/bin/env python3
# Converts Apple Passwords CSV export to Bitwarden CSV import format.
# Usage: python3 convert_apple_to_bitwarden.py apple.csv bitwarden.csv
import csv
import sys

if len(sys.argv) != 3:
    print("Usage: python3 convert_apple_to_bitwarden.py apple.csv bitwarden.csv")
    sys.exit(1)

with open(sys.argv[1], newline='', encoding='utf-8') as infile, \
     open(sys.argv[2], 'w', newline='', encoding='utf-8') as outfile:

    reader = csv.DictReader(infile)
    fieldnames = ['folder','favorite','type','name','notes','fields','reprompt',
                  'login_uri','login_username','login_password','login_totp']
    writer = csv.DictWriter(outfile, fieldnames=fieldnames)
    writer.writeheader()

    for row in reader:
        writer.writerow({
            'folder': '',
            'favorite': '0',
            'type': 'login',
            'name': row['Title'],
            'notes': row['Notes'],
            'fields': '',
            'reprompt': '0',
            'login_uri': row['URL'],
            'login_username': row['Username'],
            'login_password': row['Password'],
            'login_totp': row['OTPAuth'],
        })

print(f"Done — saved to {sys.argv[2]}")
