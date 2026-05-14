import { logger } from './Logger'

const TAG = 'GeocodeCache'
const MAX_SIZE = 200

export interface GeocodePreloadNode {
  poiName: string
  latitude: number
  longitude: number
}

interface CachedGeocode {
  addressDescription: string
  poiName: string
  cachedAt: number
}

export class GeocodeCache {
  private static cache: Map<string, CachedGeocode> = new Map()
  private static accessOrder: string[] = []

  private static makeKey(lat: number, lng: number): string {
    return `${lat.toFixed(5)},${lng.toFixed(5)}`
  }

  static set(lat: number, lng: number, addressDescription: string, poiName: string): void {
    const key = GeocodeCache.makeKey(lat, lng)
    GeocodeCache.cache.set(key, { addressDescription, poiName, cachedAt: Date.now() })
    const idx = GeocodeCache.accessOrder.indexOf(key)
    if (idx !== -1) {
      GeocodeCache.accessOrder.splice(idx, 1)
    }
    GeocodeCache.accessOrder.push(key)
    while (GeocodeCache.accessOrder.length > MAX_SIZE) {
      const evict = GeocodeCache.accessOrder.shift()
      if (evict) {
        GeocodeCache.cache.delete(evict)
      }
    }
  }

  static get(lat: number, lng: number): CachedGeocode | null {
    const key = GeocodeCache.makeKey(lat, lng)
    const entry = GeocodeCache.cache.get(key)
    if (entry) {
      const idx = GeocodeCache.accessOrder.indexOf(key)
      if (idx !== -1) {
        GeocodeCache.accessOrder.splice(idx, 1)
      }
      GeocodeCache.accessOrder.push(key)
      return entry
    }
    return null
  }

  static has(lat: number, lng: number): boolean {
    return GeocodeCache.cache.has(GeocodeCache.makeKey(lat, lng))
  }

  static preloadNodes(nodes: GeocodePreloadNode[]): void {
    let loaded = 0
    for (const node of nodes) {
      if (!node.poiName || node.poiName.trim().length === 0) {
        continue
      }
      const key = GeocodeCache.makeKey(node.latitude, node.longitude)
      if (GeocodeCache.cache.has(key)) {
        continue
      }
      GeocodeCache.set(node.latitude, node.longitude, node.poiName, node.poiName)
      loaded++
    }
    if (loaded > 0) {
      logger.info(TAG, `Preloaded ${loaded} nodes into geocode cache`)
    }
  }

  static get size(): number {
    return GeocodeCache.cache.size
  }

  static clear(): void {
    GeocodeCache.cache.clear()
    GeocodeCache.accessOrder = []
  }
}
