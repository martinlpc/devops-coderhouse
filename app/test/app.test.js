import test from 'node:test'
import assert from 'node:assert'
import app from '../src/app.js'

test('GET /health responde ok', async () => {
    const server = app.listen(0)
    const { port } = server.address()
    const res = await fetch(`http://localhost:${port}/health`)

    assert.strictEqual(res.status, 200)
    assert.deepStrictEqual(await res.json(), { status: 'ok' })
    server.close()
})