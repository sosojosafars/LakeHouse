import { useState } from 'react';
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
  Label,
  Select,
  SelectContent,
  SelectItem,
  SelectTrigger,
  SelectValue,
  Table,
  TableBody,
  TableCell,
  TableHead,
  TableHeader,
  TableRow,
  Badge,
  Button,
  Textarea,
} from '@databricks/appkit-ui/react';
import { sql } from '@databricks/appkit-ui/js';
import type { QueryRegistry } from '@databricks/appkit-ui/react';
import { AlertCircle } from 'lucide-react';
import { toNumber, formatBRL, formatIntPercent, formatPercent1 } from '../../lib/formatters';

const TODOS = 'Todos';

const STATUS_LABEL: Record<string, string> = {
  vendeu: 'Vendeu',
  vai_pensar: 'Vai pensar',
  sem_interesse: 'Sem interesse',
  nao_atendeu: 'Não atendeu',
};

const STATUS_BADGE_VARIANT: Record<string, 'default' | 'secondary' | 'outline' | 'destructive'> = {
  vendeu: 'default',
  vai_pensar: 'secondary',
  sem_interesse: 'outline',
  nao_atendeu: 'destructive',
};

const BOTOES_RETORNO: { status: string; label: string; variant: 'default' | 'secondary' | 'outline' | 'destructive' }[] = [
  { status: 'vendeu', label: 'Vendeu', variant: 'default' },
  { status: 'vai_pensar', label: 'Vai pensar', variant: 'secondary' },
  { status: 'sem_interesse', label: 'Sem interesse', variant: 'outline' },
  { status: 'nao_atendeu', label: 'Não atendeu', variant: 'destructive' },
];

type FilaRow = QueryRegistry['fila']['result'][number];

function KpiCard({
  title,
  value,
  subtitle,
  loading,
}: {
  title: string;
  value: string;
  subtitle?: string;
  loading: boolean;
}) {
  return (
    <Card className="shadow-sm">
      <CardHeader>
        <CardTitle className="text-sm font-medium text-muted-foreground">{title}</CardTitle>
      </CardHeader>
      <CardContent>
        {loading ? (
          <Skeleton className="h-8 w-24" />
        ) : (
          <>
            <div className="text-2xl font-bold text-foreground">{value}</div>
            {subtitle && <div className="text-xs text-muted-foreground mt-1">{subtitle}</div>}
          </>
        )}
      </CardContent>
    </Card>
  );
}

function ComoFoiALigacao({
  row,
  comentario,
  onComentarioChange,
  onSaved,
}: {
  row: FilaRow;
  comentario: string;
  onComentarioChange: (clienteId: number, value: string) => void;
  onSaved: () => void;
}) {
  const [salvando, setSalvando] = useState(false);
  const [erro, setErro] = useState<string | null>(null);

  if (row.status_retorno) {
    return (
      <div className="space-y-1">
        <Badge variant={STATUS_BADGE_VARIANT[row.status_retorno] ?? 'outline'}>
          {STATUS_LABEL[row.status_retorno] ?? row.status_retorno}
        </Badge>
        {row.comentario_retorno && (
          <div className="text-xs text-muted-foreground whitespace-normal break-words">{row.comentario_retorno}</div>
        )}
      </div>
    );
  }

  async function registrar(status: string) {
    setSalvando(true);
    setErro(null);
    try {
      const res = await fetch('/api/retorno', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          cliente_id: row.cliente_id,
          vendedor: row.vendedor,
          status,
          comentario: comentario || undefined,
          referencia: row.referencia_fila,
        }),
      });
      if (!res.ok) {
        const body = (await res.json().catch(() => null)) as { error?: string } | null;
        setErro(body?.error ?? `Falha ao gravar (HTTP ${res.status}).`);
        setSalvando(false);
        return;
      }
      onSaved();
    } catch {
      setErro('Não foi possível falar com o servidor.');
      setSalvando(false);
    }
  }

  return (
    <div className="space-y-2 min-w-[220px]">
      <Textarea
        placeholder="Comentário (opcional)"
        value={comentario}
        disabled={salvando}
        onChange={(e) => onComentarioChange(row.cliente_id, e.target.value)}
        className="text-xs min-h-14"
      />
      <div className="flex flex-wrap gap-1">
        {BOTOES_RETORNO.map((b) => (
          <Button
            key={b.status}
            size="sm"
            variant={b.variant}
            disabled={salvando}
            onClick={() => {
              void registrar(b.status);
            }}
          >
            {b.label}
          </Button>
        ))}
      </div>
      {erro && <div className="text-xs text-destructive">{erro}</div>}
    </div>
  );
}

function SemanaConteudo({
  vendedor,
  comentarios,
  onComentarioChange,
  onSaved,
}: {
  vendedor: string;
  comentarios: Record<number, string>;
  onComentarioChange: (clienteId: number, value: string) => void;
  onSaved: () => void;
}) {
  const kpis = useAnalyticsQuery('kpis_semana', {});
  const fila = useAnalyticsQuery('fila', { vendedor: sql.string(vendedor) });

  const kpiRow = kpis.data?.[0];
  const conversaoPct = kpiRow ? toNumber(kpiRow.acertos_top200) / Math.max(toNumber(kpiRow.contatos), 1) : 0;

  return (
    <>
      {kpis.error && (
        <Alert variant="destructive">
          <AlertCircle className="h-4 w-4" />
          <AlertTitle>Não foi possível carregar os números da semana</AlertTitle>
          <AlertDescription>{kpis.error}</AlertDescription>
        </Alert>
      )}

      <div className="grid grid-cols-1 md:grid-cols-4 gap-4">
        <KpiCard
          title="Contatos da semana"
          loading={kpis.loading}
          value={kpiRow ? String(toNumber(kpiRow.contatos)) : '—'}
          subtitle={kpiRow ? `${toNumber(kpiRow.vendedores)} vendedores` : undefined}
        />
        <KpiCard
          title="Receita esperada"
          loading={kpis.loading}
          value={kpiRow ? formatBRL(kpiRow.receita_esperada) : '—'}
          subtitle="estimativa: score × ticket médio"
        />
        <KpiCard
          title="Conversão prevista"
          loading={kpis.loading}
          value={kpiRow ? formatIntPercent(conversaoPct) : '—'}
          subtitle={kpiRow ? `taxa base às cegas: ${formatPercent1(kpiRow.taxa_base)}` : undefined}
        />
        <KpiCard
          title="Já trabalhados"
          loading={kpis.loading}
          value={kpiRow ? String(toNumber(kpiRow.ligacoes_registradas)) : '—'}
          subtitle={kpiRow ? `${toNumber(kpiRow.viraram_pedido)} viraram pedido` : undefined}
        />
      </div>

      <Card className="shadow-sm">
        <CardHeader>
          <CardTitle className="text-base">Fila desta semana</CardTitle>
        </CardHeader>
        <CardContent className="space-y-4">
          {fila.loading && (
            <div className="space-y-2">
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
              <Skeleton className="h-10 w-full" />
            </div>
          )}

          {fila.error && (
            <Alert variant="destructive">
              <AlertCircle className="h-4 w-4" />
              <AlertTitle>Não foi possível carregar a fila</AlertTitle>
              <AlertDescription>{fila.error}</AlertDescription>
            </Alert>
          )}

          {fila.data && fila.data.length === 0 && (
            <Empty>
              <EmptyHeader>
                <EmptyTitle>Nenhum contato para {vendedor === TODOS ? 'a fila' : vendedor}</EmptyTitle>
                <EmptyDescription>
                  {vendedor === TODOS
                    ? 'A fila desta semana está vazia.'
                    : 'A fila é global: quem tem carteira mais quente recebe mais contatos, então é normal um vendedor ficar sem nenhum nesta semana.'}
                </EmptyDescription>
              </EmptyHeader>
            </Empty>
          )}

          {fila.data && fila.data.length > 0 && (
            <div className="overflow-x-auto">
              <Table className="table-fixed w-full">
                <TableHeader>
                  <TableRow>
                    <TableHead className="w-[50px]">Ordem</TableHead>
                    <TableHead className="w-[220px]">Cliente</TableHead>
                    <TableHead className="w-[120px]">Vendedor</TableHead>
                    <TableHead className="w-[80px]">Chance</TableHead>
                    <TableHead className="w-[260px]">Motivo</TableHead>
                    <TableHead className="w-[240px]">Sugestão</TableHead>
                    <TableHead className="w-[260px]">Como foi a ligação</TableHead>
                  </TableRow>
                </TableHeader>
                <TableBody>
                  {fila.data.map((row) => (
                    <TableRow key={`${row.vendedor}-${row.cliente_id}`}>
                      <TableCell className="whitespace-normal break-words">{row.ordem}</TableCell>
                      <TableCell className="whitespace-normal break-words">
                        <div className="font-medium">{row.razao_social}</div>
                        <div className="text-xs text-muted-foreground">
                          {row.cidade}/{row.uf} · ticket médio {formatBRL(row.ticket_medio)}
                        </div>
                      </TableCell>
                      <TableCell className="whitespace-normal break-words">{row.vendedor}</TableCell>
                      <TableCell className="whitespace-normal break-words">{formatIntPercent(row.score)}</TableCell>
                      <TableCell className="whitespace-normal break-words text-sm">{row.motivo}</TableCell>
                      <TableCell className="whitespace-normal break-words text-sm text-muted-foreground">
                        {row.sugestao ?? '—'}
                      </TableCell>
                      <TableCell className="whitespace-normal break-words">
                        <ComoFoiALigacao
                          row={row}
                          comentario={comentarios[row.cliente_id] ?? ''}
                          onComentarioChange={onComentarioChange}
                          onSaved={onSaved}
                        />
                      </TableCell>
                    </TableRow>
                  ))}
                </TableBody>
              </Table>
            </div>
          )}
        </CardContent>
      </Card>
    </>
  );
}

export function ASemanaPage() {
  const [vendedor, setVendedor] = useState<string>(TODOS);
  const [comentarios, setComentarios] = useState<Record<number, string>>({});
  const [reloadKey, setReloadKey] = useState(0);

  const vendedores = useAnalyticsQuery('vendedores', {});

  return (
    <div className="space-y-6 w-full max-w-7xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">A semana</h2>
        <p className="text-sm text-muted-foreground mt-1">
          A fila de contatos priorizados pelo modelo, para esta semana.
        </p>
      </div>

      <div className="max-w-xs">
        <Label htmlFor="filtro-vendedor">Vendedor</Label>
        <Select value={vendedor} onValueChange={setVendedor}>
          <SelectTrigger id="filtro-vendedor">
            <SelectValue placeholder="Todos os vendedores" />
          </SelectTrigger>
          <SelectContent>
            <SelectItem value={TODOS}>Todos os vendedores</SelectItem>
            {vendedores.data?.map((v) => (
              <SelectItem key={v.vendedor} value={v.vendedor}>
                {v.vendedor} ({toNumber(v.contatos)})
              </SelectItem>
            ))}
          </SelectContent>
        </Select>
      </div>

      <SemanaConteudo
        key={reloadKey}
        vendedor={vendedor}
        comentarios={comentarios}
        onComentarioChange={(clienteId, value) => setComentarios((prev) => ({ ...prev, [clienteId]: value }))}
        onSaved={() => setReloadKey((k) => k + 1)}
      />
    </div>
  );
}
