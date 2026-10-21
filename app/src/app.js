import express from 'express'
import client from 'prom-client'
import helmet from 'helmet'

const app = express()
client.collectDefaultMetrics()

app.disable('x-powered-by')
app.use(helmet())
app.use((req, res, next) => {
    res.setHeader('Permissions-Policy', 'camera=(), microphone=(), geolocation=()')
    res.setHeader('Cache-Control', 'no-store')
    next()
})

app.get('/', (req, res) => res.json({ message: 'DevOps PF API', version: '1.0.0' }))
app.get('/health', (req, res) => res.json({ status: 'ok' }))
app.get('/metrics', async (req, res) => {
    res.set('Content-Type', client.register.contentType)
    res.send(await client.register.metrics())
})

app.use((req, res) => res.status(404).json({ error: 'Not found' }))

export default app