import type { Course } from '../../api/horarioApi'

export function getCourseLabel(course: Course): string {
  if (course.codigo === 'string' || course.nombre === 'string') {
    return `Curso #${course.id} (Mock)`
  }
  return `${course.codigo} · ${course.nombre}`
}
