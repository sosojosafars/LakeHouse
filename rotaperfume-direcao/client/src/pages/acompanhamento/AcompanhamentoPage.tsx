import {
  useAnalyticsQuery,
  Card,
  CardContent,
  CardHeader,
  CardTitle,
  Skeleton,
  Alert,
  AlertDescription,
  AlertTitle,
  Empty,
  EmptyHeader,
  EmptyTitle,
  EmptyDescription,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  BarChart,
} from '@databricks/appkit-ui/react';
import { AlertCircle } from 'lucide-react';
import { toNumber } from '../../lib/formatters';

export function AcompanhamentoPage() {
  const { data, loading, error } = useAnalyticsQuery('acompanhamento', {});

  const totais = data?.reduce(
    (acc, row) => ({
      na_fila: acc.na_fila + toNumber(row.na_fila),
      trabalhados: acc.trabalhados + toNumber(row.trabalhados),
      vendeu: acc.vendeu + toNumber(row.vendeu),
    }),
    { na_fila: 0, trabalhados: 0, vendeu: 0 },
  );

  return (
    <div className="space-y-4 w-full max-w-5xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Acompanhamento</h2>
        {totais && totais.na_fila > 0 && (
          <p className="text-sm text-muted-foreground mt-1">
            {totais.trabalhados} de {totais.na_fila} contatos foram trabalhados, {totais.vendeu} viraram pedido.
          </p>
        )}
      </div>

      {loading && (
        <div className="space-y-2">
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
          <Skeleton className="h-10 w-full" />
        </div>
      )}

      {error && (
        <Alert variant="destructive">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Não foi possível carregar o acompanhamento</AlertTitle>
          <AlertDescription>{error}</AlertDescription>
        </Alert>
      )}

      {data && totais && totais.trabalhados === 0 && (
        <Empty>
          <EmptyHeader>
            <EmptyTitle>Ninguém registrou um retorno ainda</EmptyTitle>
            <EmptyDescription>
              O número aparece assim que o time marcar o resultado de uma ligação em &ldquo;A semana&rdquo; — zero não é erro,
              é o estado inicial. E é esse retorno que vira dado de treino do modelo na semana que vem.
            </EmptyDescription>
          </EmptyHeader>
        </Empty>
      )}

      {data && data.length > 0 && totais && totais.trabalhados > 0 && (
        <>
          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-base">Trabalhados e vendidos, por vendedor</CardTitle>
            </CardHeader>
            <CardContent>
              <BarChart data={data} xKey="vendedor" yKey={['trabalhados', 'vendeu']} />
            </CardContent>
          </Card>

          <Card className="shadow-sm">
            <CardHeader>
              <CardTitle className="text-base">Por vendedor</CardTitle>
            </CardHeader>
            <CardContent className="overflow-x-auto">
              <Table className="table-fixed w-full">
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[160px]">Vendedor</TableHead>
                    <TableHead className="w-[90px]">Na fila</TableHead>
                    <TableHead className="w-[110px]">Trabalhados</TableHead>
                    <TableHead className="w-[90px]">Vendeu</TableHead>
                    <TableHead className="w-[100px]">Vai pensar</TableHead>
                    <TableHead className="w-[120px]">Sem interesse</TableHead>
                    <TableHead className="w-[110px]">Não atendeu</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {data.map((row) => (
                    <TableRow key={row.vendedor}>
                      <TableCell className="whitespace-normal break-words font-medium">{row.vendedor}</TableCell>
                      <TableCell>{toNumber(row.na_fila)}</TableCell>
                      <TableCell>{toNumber(row.trabalhados)}</TableCell>
                      <TableCell>{toNumber(row.vendeu)}</TableCell>
                      <TableCell>{toNumber(row.vai_pensar)}</TableCell>
                      <TableCell>{toNumber(row.sem_interesse)}</TableCell>
                      <TableCell>{toNumber(row.nao_atendeu)}</TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </CardContent>
          </Card>
        </>
      )}
    </div>
  );
}
