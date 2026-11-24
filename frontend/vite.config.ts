import react from '@vitejs/plugin-react'
import { defineConfig, loadEnv } from 'vite'

export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), '')
  const proxyTarget = env.VITE_API_PROXY_TARGET || 'http://localhost:4010'
  const mockMode = mode !== 'production' && new URL(proxyTarget).port === '4010'

  return {
    plugins: [react()],
    define: {
      'import.meta.env.VITE_API_MOCK_MODE': JSON.stringify(String(mockMode)),
    },
    server: {
      proxy: {
        '/api': {
          target: proxyTarget,
          changeOrigin: true,
          rewrite: (path) => path.replace(/^\/api/, ''),
        },
      },
    },
  }
})
