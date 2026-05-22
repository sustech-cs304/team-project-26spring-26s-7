#!/usr/bin/env node
'use strict'

const { AGCClient, CredentialParser } = require('@agconnect/common-server')
const { AGCAuth } = require('@agconnect/auth-server')

function readStdin() {
  return new Promise((resolve, reject) => {
    let data = ''
    process.stdin.setEncoding('utf8')
    process.stdin.on('data', chunk => {
      data += chunk
    })
    process.stdin.on('end', () => resolve(data.trim()))
    process.stdin.on('error', reject)
  })
}

function valueOrEmpty(value) {
  return value === undefined || value === null ? '' : String(value)
}

function shouldCheckRevoked() {
  const raw = valueOrEmpty(process.env.AGC_CHECK_REVOKED).trim().toLowerCase()
  return raw === '1' || raw === 'true' || raw === 'yes'
}

function parseJwtHeader(token) {
  const headerPart = token.split('.')[0] || ''
  const padded = headerPart.padEnd(headerPart.length + ((4 - headerPart.length % 4) % 4), '=')
  return JSON.parse(Buffer.from(padded, 'base64url').toString('utf8'))
}

async function main() {
  const credentialPath = process.argv[2]
  if (!credentialPath) {
    throw new Error('missing credential path')
  }

  const accessToken = await readStdin()
  if (!accessToken) {
    throw new Error('missing access token')
  }

  try {
    const header = parseJwtHeader(accessToken)
    process.stderr.write(`token_header alg=${valueOrEmpty(header.alg)} kid_present=${header.kid ? '1' : '0'}\n`)
  } catch (_) {
    process.stderr.write('token_header parse_failed\n')
  }

  AGCClient.initialize(CredentialParser.toCredential(credentialPath))
  const verified = await AGCAuth.getInstance().verifyAccessToken(accessToken, shouldCheckRevoked())
  const uid = valueOrEmpty(verified.getSub())
  if (!uid) {
    throw new Error('verified token missing subject')
  }

  process.stdout.write(JSON.stringify({
    uid,
    aud: valueOrEmpty(verified.getAud()),
    iss: valueOrEmpty(verified.getIss()),
    exp: verified.getExp() ?? 0,
    iat: verified.getIat() ?? 0,
    email: valueOrEmpty(verified.getEmail()),
    phone: valueOrEmpty(verified.getPhone())
  }), () => process.exit(0))
}

main().catch(err => {
  process.stderr.write(err && err.stack ? err.stack : String(err))
  process.exit(1)
})
