export async function register() {
    if (process.env.NEXT_RUNTIME === 'nodejs') {
        const mod = await import('./instrumentation.node')
        if (typeof mod.register === 'function') {
            mod.register()
        }
    }
}
