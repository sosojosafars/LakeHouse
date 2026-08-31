import { createApp, analytics, genie, server, getExecutionContext } from '@databricks/appkit';
import { z } from 'zod';

const RETORNO_STATUS = ['vendeu', 'vai_pensar', 'sem_interesse', 'nao_atendeu'] as const;

const retornoSchema = z.object({
  cliente_id: z.coerce.number().int(),
  vendedor: z.string().min(1),
  status: z.enum(RETORNO_STATUS),
  comentario: z.string().max(500).optional(),
  referencia: z.string().regex(/^\d{4}-\d{2}-\d{2}$/, 'formato aaaa-mm-dd'),
});

createApp({
  plugins: [
    analytics(),
    genie(),
    server(),
  ],
  // 200 linhas, e todas mudam quando alguém clica em um dos botões de
  // retorno — não vale a pena cachear a leitura.
  cache: { enabled: false },
  onPluginsReady(appkit) {
    appkit.server.extend((app) => {
      // E-mail de quem está logado, para a aba "Perguntar" — não é consulta
      // ao warehouse, então fica fora de config/queries/.
      app.get('/api/quem-sou', (req, res) => {
        const email = req.headers['x-forwarded-email'];
        res.json({ email: typeof email === 'string' ? email : null });
      });

      // A única rota que escreve. Leitura continua exclusivamente em
      // config/queries/ — este endpoint nunca faz SELECT.
      app.post('/api/retorno', async (req, res) => {
        const parsed = retornoSchema.safeParse(req.body);
        if (!parsed.success) {
          res.status(400).json({
            error: `status precisa ser um de: ${RETORNO_STATUS.join(', ')}`,
            detalhe: parsed.error.flatten(),
          });
          return;
        }

        const { cliente_id, vendedor, status, comentario, referencia } = parsed.data;
        const emailHeader = req.headers['x-forwarded-email'];
        const registradoPor = typeof emailHeader === 'string' ? emailHeader : 'dev-local@rotaperfume.com';

        try {
          const { client, warehouseId } = getExecutionContext();
          const resolvedWarehouseId = await warehouseId;
          if (!resolvedWarehouseId) {
            res.status(500).json({ error: 'Warehouse não configurado no contexto de execução.' });
            return;
          }

          const response = await client.statementExecution.executeStatement({
            warehouse_id: resolvedWarehouseId,
            wait_timeout: '30s',
            statement: `
              INSERT INTO lakehouse_rotaperfume.gold.retorno_ligacao
                (cliente_id, vendedor, status, comentario, registrado_em, registrado_por, _referencia)
              VALUES
                (:cliente_id, :vendedor, :status, :comentario, current_timestamp(), :registrado_por, :referencia)
            `,
            parameters: [
              { name: 'cliente_id', value: String(cliente_id), type: 'INT' },
              { name: 'vendedor', value: vendedor },
              { name: 'status', value: status },
              { name: 'comentario', value: comentario },
              { name: 'registrado_por', value: registradoPor },
              { name: 'referencia', value: referencia, type: 'DATE' },
            ],
          });

          if (response.status?.state !== 'SUCCEEDED') {
            res.status(502).json({ error: 'O warehouse não confirmou a gravação.', detalhe: response.status });
            return;
          }

          res.status(201).json({ ok: true, registrado_por: registradoPor });
        } catch (err) {
          res.status(502).json({ error: 'Não foi possível gravar o retorno.', detalhe: String(err) });
        }
      });
    });
  },
}).catch(console.error);
