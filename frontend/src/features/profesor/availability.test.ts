import { describe, expect, it } from 'vitest'
import { parseAvailabilitySlots } from './availability'

describe('validación de intervalos de disponibilidad', () => {
  it('convierte días y HH:MM a la franja entera del contrato', () => {
    expect(parseAvailabilitySlots([{ day: '1', start: '08:15', end: '10:00' }])).toEqual([
      { dia: 1, inicioMin: 495, finMin: 600 },
    ])
  })

  it('permite 24:00 únicamente como fin y lo convierte a 1440', () => {
    expect(parseAvailabilitySlots([{ day: '7', start: '23:00', end: '24:00' }])).toEqual([
      { dia: 7, inicioMin: 1380, finMin: 1440 },
    ])
  })

  it.each([
    { day: '0', start: '08:00', end: '09:00' },
    { day: '8', start: '08:00', end: '09:00' },
    { day: '1', start: '24:00', end: '24:00' },
    { day: '1', start: '08:00', end: '08:00' },
    { day: '1', start: '09:00', end: '08:00' },
    { day: '1', start: '08:00', end: '25:00' },
    { day: '1', start: '08:00', end: '12:60' },
  ])('rechaza una franja inválida: $day $start-$end', (draft) => {
    expect(() => parseAvailabilitySlots([draft])).toThrow()
  })
})
