import { describe, expect, it } from 'vitest'
import { formatMinutes, parseTime } from './time'

describe('conversión de horas de disponibilidad', () => {
  it('formatea minutos desde medianoche como HH:MM', () => {
    expect(formatMinutes(480)).toBe('08:00')
    expect(formatMinutes(725)).toBe('12:05')
  })

  it('representa el fin del día como 24:00', () => {
    expect(formatMinutes(1440)).toBe('24:00')
    expect(parseTime('24:00', true)).toBe(1440)
  })

  it('convierte horas del formulario en minutos enteros', () => {
    expect(parseTime('08:30')).toBe(510)
    expect(parseTime('23:59', true)).toBe(1439)
  })

  it('rechaza horas inválidas y 24:00 como hora de inicio', () => {
    expect(() => parseTime('24:00')).toThrow()
    expect(() => parseTime('8:00')).toThrow()
    expect(() => parseTime('25:00', true)).toThrow()
    expect(() => parseTime('12:60', true)).toThrow()
  })
})
