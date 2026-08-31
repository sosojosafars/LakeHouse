// O warehouse devolve DECIMAL/DOUBLE como STRING no JSON mesmo quando o tipo
// gerado diz `number` — sempre converter antes de formatar ou somar.
export const toNumber = (value: number | string | null | undefined): number =>
  value === null || value === undefined ? 0 : Number(value);

export const formatBRL = (value: number | string | null | undefined): string =>
  toNumber(value).toLocaleString('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  });

export const formatIntPercent = (value: number | string | null | undefined): string =>
  `${Math.round(toNumber(value) * 100)}%`;

export const formatPercent1 = (value: number | string | null | undefined): string =>
  `${(toNumber(value) * 100).toLocaleString('pt-BR', { maximumFractionDigits: 1 })}%`;
