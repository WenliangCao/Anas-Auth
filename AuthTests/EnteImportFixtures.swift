// 来自 ente 仓库的导入测试样本（mobile/apps/auth/test/ui/settings/data/import/fixtures），
// 均为测试用的假账号，用来确认本 App 与 ente 的解析结果一致。
enum EnteImportFixtures {
    static let otpAuthBackup10 = #"WlczAK6JaEq0M0qfB5XzwTAMzMcc2lwoHJeUz33MSemJoleIQgh7RTeN7LzSv8m3bDt0RmpkLy7fAa0P3nevT7w2VTbmGrPZu0lPjShFuCc7+Z4U88qGcffzDRzJxlsnHnk5nN1NITxthny1UoulJEJiBgptM9IWUO2U7uRCLUu2CIWYeKboCiL/zVHQrrKxc+uiPDTHreWu1iVx7lVuzo0j4LEr6msqaZyHELW3ZRCUtJTuWisYUcRTjjKjn0OKXnjrd6a4dN/yAwOmkmf9Y1BS6ZzP6ypBlqOJmoxdyCXUMGZAlESlBOZnUaOMBHtphJ8YQEXr2T7VsuBVxb1RStu35HNbkes/4k94sWjB1S+ZKAVe25P5iw5YX6dUxhPhow1+BgiCIAw62ZlyL+J0jUX/j+544wqDlndFqh96i95TSZ66jBS0m5ncxbDszaCJDw/8ikG9x1s50dcl89Sp4upMR/PVpx/nzhabUeook987qw//Bs+xMbuD4CJkI6JmQdKxzHPC+RWxOMPlYL2W1OteqTkTpkLlGF1ko2GiMeuMTEWggXDvdvz9GP3FUntf4LVzyFtHIWPNKEvsIqAZAzRXPaWDBgp+hhmNqQp6OARTpyzCj0G0BKn1SEl6L1TlhPuWpM72wbMG4NFltGoTA/vuVQ7E/JKt8gILilDE9sB+GQ21r1LAou8Ce8jDAo55WoNC5FuzJ68I7l2SJOWHVbMazrbLh+Hq79vVVsF7lEn/4T/y636xae4QkYTRV6lL6VaaiSqnm8rOSkJUZt5uQV6MhvgwLItGYa/TQVjC6eQwo/W7F2v8QJpPearOaq0Zdj4cZk6+7LEG4H5GUXGDxpF0MZl3yBChUDK7MHfw6UQbAGP04fil1zEC9u8qcyWE4jYjf9RvPIxEn44lGJ0dNK6giKCnsW7TDeaFUMBMM9U3APewCgKz06MlwrjXGn3Cwfj+jm9jXP3Sa7L5G5FVLaT68bl5A0QnhU2PCqzhYknR8gHAM4gWZcphXiQk7QW+s+xdtph4h0lZif6WE1NDsFWjWT2i7DSXi+/yCfagoNMl/Qa5Z+KdgPXtNgJiVHpQZAmt8ZEs3SFwuVYU+FdP5ZAzL1Adb9mREBx0k3iXKRfKidxJYan8TQsQYC4IblrB1bHHiWMNcTZiIBjWKbudKgwllMUPYra58kmCw9Yxtm14E87bpB3Lf1cfFq+KexnWp5uPCDIwcfoUySSwDkEN20KfStpRBu70YrDD3GsGQJaMDQOq7SZ7RpCW0b0JWYfOjDKOm0nqVDddcyqKwha+4hrZVYW3N90WM7uJNsMxJ5Xvd30T0PkypzNhrpubLLR+w7O8DsK/mhWdfXCVdVAvLqM7bORUOOEpm5vFZZGczWsLfH46XJj40QawOP45HYvebS0kLuHGAyToIi6XYWaB7sXgCKKa0P+wX/gY/VhTx5odCfVgTPfZJlqK3Oyh9fCLOBKtUKh5dlaykMv4M/QS361J/NsuhkKcjhSPuch8THjM/fLkF6AoqX38Mw4xhYgFWbxMUTKENBN5tVsh5f3Xw+KVvrEb4FViLE3GXyMdl1M="#
    static let otpAuthBackup11 = #"0JFoxrF9x6Mf5243XHhzyjZmFoJKcvaRc/PnYb4G2lcWMyPXEmuoC0fIzQlYH1mOIqyc8DsZaorw2P8xIunZVtzREC3xm+A4fvXiaqZIAdPtIf0hXUxi9xdGTXVrlEzlfVQksCiQA0lKfi3X8YNIAQp3f5R5qRWMj5C1mrNhO5t2Ax9cj6+LK+Md66uynCEBD6Nd30pcfrU6e+NrjlcnyUKDts0QXwoJv/1U3gCniUOx/NGKOhfHiTQET3hGfoKR4cqDaYNNNXj29IDqAGAfsSehSxhjvBCgb/dSMNsFxl3rGmR9yvsw2xkFOZjP1nYpZX8KKlsR9dS3DFiPanvNEdZ/m0JJRF/h5meWnuK3mLOE0H0G4PD6nvhx0LJINZsZtuGKJ4egOBClBlR4NfXZsqGW3IzbaUkyDNSxMhK8LzMtOdUy2lXkeSl+enQZFPFXNlY3KYXSDx8cbLw6baw+8yg2QQCu9PBaUhVmM4JDDYWQzJzWMMACnhJ07kH7nZ09+p8SKuRkqbmcaEMNQp/dSAHdvGWQkzqHLB9TShPtNtAafrm1BaG4GbL0J7F/+Y4BMJY25xe+bc/P0aPKw6W5e2d+DAjVgrjpNmFf4xDGtYF7xkh91YqwiK0iV8C/Mp6UG3OK7uQNIWNXPWHle1CWGxIdXSDCJQHgneTFq5Vik9RbHyIqCyzoMOw/bgdBi+UPmLKeURz/BTc5voks/wJX8XGmEZ8I3hj7NILCgkPCMEBfuyUgbh2U1eWrXDFgEqE2hBSVv48tl3dU/aq1/fXR76q/j9F876qRJ02H7GuDL5ZY5iox3UY2MbFbrtO6wAZaPW91io4B+bQCMpJJxoTV3OIOvtHxPfqcOz9qEOzGShYjJ/BssWZYwyb7pLOoORbeNrP7B4ZF1JVjB6AKN9P69j7oVmSlca6l78wYOMcZ3kpgPUxVBNfu2jkUA8naY3dtwqMwgF8S/Y9z1/nnoUZCFkW8evltG86YdCseeLIXEAHs7PRNjTXMmJwGICkX+az1NY4pPX6+nNI1FHmi3WC+pSNJhs8fCQa+H/awxh/0V9ITiR6zKBHt2dRpN/ZsB/Pq/VUB9EQK2ybnMkIrGwsXFneFAouBEeOTjZJ+/20Nv2jp3GDlIDx8xnwRpIil2uIF6wpcUt1ExuwZHzIAAyNACdYF4avxllsteUAxLQ2ymXOmFk71drV+LvnTsxgvEYVs2Qbt3mFvk0nkOBnF3iwlEWm02OaIxClAzq8fS3AUBYVO3u23AVkWTkKJbmI7sdV1XQjkiZusjioIH935vH1No6DDJ95OT5wA0X+xnfhhcyG8OmFgKkWAXnfbC2wo4jA3xE79mv7PP7aONV5IAchzHDuT7q90rfU01MbYV/ygKsBVdqVHNZRSiv/fYahNjmK6X/Y2EK/wSKCmLLRXOcPGrlRetICVFWnxq1pHvL/yjq7hWgM/UfrvCKB5NTxka4V/5fVwyvfdSqzsy4mZaUw1DhPhbrLBlIfafMR+AupWaUetc7gbT5pGuFxpDnSg7HUFhTtp9fZjOziNb6nX9b8oqQ=="#
    static let otpAuthAccount11 = #"vPpZTR551tpxtoXMHnZRn5nFYZTxgBCQCTYPb6P6s38y3U0ZkO6ofRox5zcU/uopjnscDzmuducJSJYggakxQZ1LhQ2ViFLTd8I7LQnvKRB+65caEicMVi0WNmMo+/4j2dMpDff+O8m75p/lM60tfktIS2DPE1d8hHkgnC34eVpH2wi00WY7ZxnUUkTzoa2gn7HiUGTA7vMeTa0im5unpRoA3cEt2yE4yLwgKEazA8IJ0uicEePsiZQJleGTH7KPSGn4sGQdvqfhCn6ddwlXXPXX04QnwMSek/38I2i27JMURgc6jJVqfei3OtssKSXY4dYCapuC1X/nLpCWfYRF+Zef0RdeuBLEH5rjP4ME+iNhO4aTX30JnSC1PLoX9Z/AR7Yvrv5IFGF3hxESucmgJiCDdyMC5iDGR2+/eVVQdUV43gJvvMr9C6HmC3S+4CsSwteSpje22kUFkUVP862siSVPZA145XWsSmcbC95Gx4UNmidvxzzS3ToxafwsYz+xqJ8w2+a6JVOR+Z1pZN6Ap7QV4r4uzGlkkIbX1+k6zPCqR0E6SYQFOtsmK4dS1Zk0PuTeP7cW1350w/VJ1Al6VmmScGkSROg9pLhD0bgpk+0sv3fpC3gD1JCf9DzdrtZhb5Vt3d1E1RIy50yRBaExqShZt/1DbFYV6WmOBwZ1zJAz0+Rg0Lge+dup05qncRjM85au+mSAqk97iPv+ro2fTrhF0FWAn0agd09xnp+Er+X5RtkXX8kRGOBjfWE7gJuKNEKrM9XwfkPnoqa90rGEWM3Sc7LEE72tQvtuBti9gofj3OMV+t0rOEllPlaFsUxcM1WAuwVg7hkyAErlpXD8o9sTrxwUWWPue8fKn0upd+mJ4SryEeiqzbLbSWFnggSwJMLt8IrZFYkRp8sDq0EuQvVDJxrExkrIICNUm1EyuRlOfbT/+XMTkWqMTdYjmu9dcYPZnIj78uihw0pUPU/ZIJL8uC/gl4BhgM69GYQoymuVX5WcrxSjtVuLKVu+utugS352Xh03UqOTrc2+ebHiBzEfKtm4qXUq3uvzafTtTIBQsqjYd/VLQu9lHi882CUnrk11RATZ+d88aig6bbZj94peoVXmCmozEXvLvC+NsFO5iT9pbUVwgjokYlVP+xfc"#
    static let otpAuthAccount12 = #"6B7TbRpKxBWAbgx6gC0LqXP4tdaJkmiRWyWKVdD/3Xj+Z/kskrD6oDZQvTY+LeExaYRbrfJQ6mLazdgRRGPLb5WUVOaDbNYrm2+1qtOy7TSMXitIZdmeklPhKH/AbGIXmdnfaPV3NOUj4M9csMYta+gkV4XAF3aydaHGY7emAAUoQbZSpHQdd4xIZqampyNXsJpA1aTk/x7Z6lE882RbjbjNvHCP8HZV7pld4/3Y1xpQ8qYiYxBgkipceSfYN/NFnkilr1PE8+ftzwlqa2i/4DBwN7aJqWpfqfhcPjjCnNkKJ+21WQEFtuKen0mzcWoCtvx8ISrcfD7cSPRCY/9hXVMPy6MRu+Yis3z1qk0gIqeuIfQxZid1OqHtyf3BKyXB4R2Htu+TMWZEC6NP8wCiQ3zKWAGQz9BewxXT8uHYm/Gdwqb+ASrvFfLrFGIFidPLsGh7OKzDhx/B7YT5cymT3nZjk41cHJyRl7qn1kpVQXp3CU5WCNiOUsRrVx6W1BGgtiVshikjGTT8L/NKWIXkcc5+xQO6j67/tP+DD8S7rDGpUhUmuMqpgOapT51ZaLHMDUp3ZKsUH+P9ieA+jmCbL+81/gmID5uEkALuYITdkb7dGMtTiktG2ht/tc7ae9sUdTpyhJmhLmaqFu2C60lbm+PORUCAGSFmy0SIve7141d7GI5B4QrAl0aXwBE/BukdBe2/PuqA+PyV4AFwFBbkMjpgQVoWpITC3SW/hJUqq6byrQULOfCccqPNcQiCSguSaPqYMV7TmUJrMblIpGMaSSopiCfaksLOkwL4VK+mCkqiAzEz9zUclyVWgEJcKzrzJUaE0z6g9wClfejo1EEun4Iut3mdW27W+L6zmtGLVFzmdX7XZUby/7+61wEexQLllkKMJ/fjor/ZVpGth2Wm+9V37peJ2HealCT/0XYvVElixwid1nzSRs8ZNvOmmSXe8XOLXKRMYyy/ntE1P9BNHrbfGmUmhSH6YVK7l5BzReUETnZHgDFzZ7K0A4MTSWFhC5CRQKUXR0G15ZsY1fXHNE9hoZgLnxcB6Kzyt+M5JD5ZmTPHLgubusFUDGdLSczN0vGtscJNzUInOI+aCDexNVleEdyQ9kgTMa0Ug4AQInwFqQqYko+LBecsPeFmGCwN"#
    static let protonPlain = #"{"version":1,"entries":[{"id":"1ccf0766-1121-4443-8cd2-25ce991384c3","content":{"uri":"otpauth://totp/example%40ente.io?secret=MI4GCOJSGIZTKLJSGMZWKLJUGEZDQLJYG5STILJSMUYDIYTCMQ3TSOJRGI&issuer=.env&algorithm=SHA1&digits=6&period=30","entry_type":"Totp","name":"example@ente.io"},"note":null},{"id":"66b886aa-a764-427a-acde-8c5368d63482","content":{"uri":"otpauth://totp/%3Acool%40ente.com?secret=554VBDOGJRLDG2JV&issuer=%2Fe%2F&algorithm=SHA1&digits=6&period=30","entry_type":"Totp","name":":cool@ente.com"},"note":null},{"id":"d8a85eb1-2e84-418d-b764-e2d0868ee66a","content":{"uri":"otpauth://totp/simple%40ente.sh?secret=PIBTGMBYQYVSLN5PVZYQUTKYHOBRYYT7&issuer=ente&algorithm=SHA1&digits=6&period=30","entry_type":"Totp","name":"simple@ente.sh"},"note":null},{"id":"3a481750-197b-4c02-8d1e-086068f55a54","content":{"uri":"otpauth://totp/r%40ente.com?secret=J4YFC3TZKVYWCVCNIVBWIV2GHFAXUNDF&issuer=reddit&algorithm=SHA1&digits=6&period=30","entry_type":"Totp","name":"r@ente.com"},"note":null}]}"#
    static let protonEncrypted1231246 = #"{"version":1,"salt":"vNtIiEoQj5sUZuxE741QcQ==","content":"8991powlER+W23SaPHzkOMp3jRmoap8p2/nm01jjDVNyLqpkIpyA/LCzE7Dx8KMf8JSOOyJAdg9PSoP6VXv2Emvc28SGdtnnqgL1kml8TEmoE0QhplXYL8E15xTrmEYeghbd4yog5FpqdcMYrgrOfUuWoeSXzHz+hQ9jGP+YKDpmUdWRHE4E3BHN2iyPEBZegc8uCDD/ThkPGZTWn4y5qMuUKs0s0g+og86Z2XHZnkRruHvgvBUMEzxfKz4ietyMorKf+92olXjHYv8CCbqPOMvCjf6lAv/X/BPluX/+fPFq5eQPdYECdkNvA6R1Ov18gjzjddvUDIHTnSG9VNnlta5/MYeSRVoQ4qTtxoeTOpkyXPbsptr32zs8QcDM+5Ek8Trdvs170dmCjFmNCZuhiQcbPjsaX0BQTowFHF/32YyKHTJ3ZsgDJY9Ppm8Af4SmZuw2jypbOdsAubGhKEujzgIVr5Agao3hkLKP//b5Rgxng4xUD5lx30Opvzok9AhPu2yFa97SMknx0lXCg9MPPksLLEfBY5HDXwjFJ3F4E6ZsJEU0OGM11WR66IjDx+U8Fr4cxrk0tvHA/iEwxEnhAMCrcpWJFmyHZiSGqdkodYB2ahe6Wi19hzo4ddXC2I8liBWvBQLLnWk8HSwXn80XfPWLt08zqD8BPfbOTtpGHwxIVJ3fPZKlJECLc9YKjDLW7MttqNjCKvgcQrkKh6U3NYHUwykHX6m2P+1O1DwE/B15f1Sy0l/yL+YrVX5Ijz8WIixZKlCNsjOa7WCPTfDNPZuD30G5n6UHHrSbN/7FdQKdOT149JJf1iD6uLae8YnpYS68PEevURq7UuGTd7sEkGBrPgHPaT6wB+Tj1DZx4FxAgu3GIIbMjbng3KywjlzYbp3NehawDzStoc0iFA6rSzQuZn2e5GqUgNlQXpNwMg4i2CHQ2smx8MLddKEVT7Ho9llqZvFoIl+hI4MHXhySpNHH1qLgVE0QVdziUVQ0MBzW4JnFA0Vzvk8tCTG0lai766vrTrB619kpdwNi9qpUEX1JPnD2nzAkUVHhfzvxf9VpFlwhAgMyuKnDUdNUxTuhPIJhjfB4GOvjrsO8QFh5uuiIe65o3XdyfttFUM5nxusKKPyQEXILFFtRyshwxQU0bdzxd9jNFC8xp0wkhGgWiBsF2WoUOw2Vq6HEhudJ3LlVv263hFpcYEsNO3iN0vZpBgzECXOeXIwUGb7ntC+IgYisX35jEtxiQO6M592REybEom0pe2nPcCvU9QCjIP+VDtu5fYSVHNZGI57DMPu5TsCrkH02b8uZ98IiPyLS35hVW7s2XcAIwul8rbCc6AKzHfuwh+N3JnmDyidn8ERrWw=="}"#
    static let entePlainText = #"""
otpauth://totp/GitHub:release.bot@github.demo?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30
otpauth://hotp/Yubico:lab-counter@yubico.demo?secret=ASKZNWOU6SVYAMVS&issuer=Yubico&algorithm=SHA1&digits=6&counter=1
"""#
    static let enteRichJSON = #"""
{
  "items": [
    {
      "rawData": "otpauth://totp/GitHub:octocat@github.demo?secret=JBSWY3DPEHPK3PXP&issuer=GitHub&algorithm=SHA1&digits=6&period=30",
      "display": {
        "pinned": true,
        "trashed": false,
        "lastUsedAt": 1720000000,
        "tapCount": 12,
        "tags": ["Work", "Admin"],
        "note": "Primary admin account. Keep recovery contacts current.",
        "position": 0,
        "iconSrc": "",
        "iconID": ""
      }
    },
    {
      "rawData": "otpauth://totp/Dropbox:archive.bot@dropbox.demo?secret=KRSXG5DSNFXGOIDB&issuer=Dropbox&algorithm=SHA1&digits=6&period=30",
      "display": {
        "pinned": false,
        "trashed": true,
        "lastUsedAt": 0,
        "tapCount": 0,
        "tags": ["Time capsule", "Archived"],
        "note": "Intentionally kept in trash for restore testing.",
        "position": 4,
        "iconSrc": "",
        "iconID": ""
      }
    },
    {
      "rawData": "otpauth://totp/Stripe:treasury%2Bauth@stripe.demo?secret=MFRGGZDFMZTWQ2LK&issuer=Stripe&algorithm=SHA256&digits=8&period=45",
      "display": {
        "pinned": false,
        "trashed": false,
        "lastUsedAt": 1710000000,
        "tapCount": 5,
        "tags": ["Money moves", "Finance"],
        "note": "Eight-digit SHA-256 code for the demo treasury.",
        "position": 1,
        "iconSrc": "",
        "iconID": ""
      }
    },
    {
      "rawData": "otpauth://steam/Steam:speedrunner@steam.demo?secret=ONSWG4TFOQXG64RA&issuer=Steam",
      "display": {
        "pinned": true,
        "trashed": false,
        "lastUsedAt": 1700000000,
        "tapCount": 20,
        "tags": ["Game night"],
        "note": "Steam-compatible five-character code.",
        "position": 2,
        "iconSrc": "",
        "iconID": ""
      }
    },
    {
      "rawData": "otpauth://hotp/Yubico:lab-key-42@yubico.demo?secret=ORSXG5AAMFZGK3TH&issuer=Yubico&algorithm=SHA512&digits=6&counter=42",
      "display": {
        "pinned": false,
        "trashed": false,
        "lastUsedAt": 0,
        "tapCount": 0,
        "tags": ["Hardware keys", "Lab"],
        "note": "HOTP fixture for counter advancement.",
        "position": 3,
        "iconSrc": "",
        "iconID": ""
      }
    }
  ]
}
"""#
}
