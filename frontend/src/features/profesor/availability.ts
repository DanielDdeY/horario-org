import type { AvailabilitySlot } from '../../api/horarioApi'
import { parseTime } from './time'

export interface AvailabilityDraft {
  day: string
  start: string
  end: string
}

export function parseAvailabilitySlots(drafts: AvailabilityDraft[]): AvailabilitySlot[] {
  return drafts.map((draft) => {
    const dia = Number(draft.day)
    const inicioMin = parseTime(draft.start)
    const finMin = parseTime(draft.end, true)

    if (!Number.isInteger(dia) || dia < 1 || dia > 7) {
      throw new Error('Selecciona un día válido para cada intervalo.')
    }
    if (finMin <= inicioMin) {
      throw new Error('La hora de fin debe ser posterior a la hora de inicio.')
    }
    return { dia, inicioMin, finMin }
  })
}
