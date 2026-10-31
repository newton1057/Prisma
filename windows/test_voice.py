import json
import os
from common import send
payload = {'text': os.environ.get('PRISMA_TEST_TEXT', 'Hola. Prisma está funcionando.'), 'cwd': os.getcwd()}
for key in ('engine', 'voice'):
    value = os.environ.get('PRISMA_TEST_' + key.upper())
    if value: payload[key] = value
print(json.dumps(send(payload)))
