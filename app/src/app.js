import express from 'express'
import client from 'prom-client'

const app = express()
client.collectDefaultMetrics()

app.get('/', (req, res) => res.json({ message: 'DevOps PF API', version: '1.0.0' }))
app.get('/health', (req, res) => res.json({ status: 'ok' }))
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', client.register.contentType)
    res.send(await client.register.metrics())
})

export default app