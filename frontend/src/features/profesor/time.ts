export function formatMinutes(minutes: number): string {
  if (!Number.isInteger(minutes) || minutes < 0 || minutes > 1440) {
    throw new RangeError('Los minutos deben ser un entero entre 0 y 1440.')
  }

  if (minutes === 1440) return '24:00'
  const hours = Math.floor(minutes / 60)
  const remainder = minutes % 60
  return `${String(hours).padStart(2, '0')}:${String(remainder).padStart(2, '0')}`
}

export function parseTime(value: string, allowEndOfDay = false): number {
  if (allowEndOfDay && value === '24:00') return 1440
  const match = /^([01]\d|2[0-3]):([0-5]\d)$/.exec(value)
  if (!match) throw new Error('Usa el formato HH:MM; 24:00 solo es válido como hora de fin.')
  return Number(match[1]) * 60 + Number(match[2])
}
