import { useEffect, useState } from 'react';
import { GenieChat, Alert, AlertDescription, AlertTitle } from '@databricks/appkit-ui/react';
import { Info } from 'lucide-react';

export function PerguntarPage() {
  const [email, setEmail] = useState<string | null>(null);

  useEffect(() => {
    fetch('/api/quem-sou')
      .then((res) => res.json())
      .then((body: { email: string | null }) => setEmail(body.email))
      .catch(() => setEmail(null));
  }, []);

  return (
    <div className="space-y-4 w-full max-w-4xl mx-auto">
      <div>
        <h2 className="text-2xl font-bold text-foreground">Perguntar</h2>
        <p className="text-sm text-muted-foreground mt-1">
          {email ? `Logado como ${email}. ` : ''}
          Pergunte qualquer coisa sobre a fila, o modelo ou os retornos de ligação.
        </p>
      </div>

      <Alert>
        <Info className="h-4 w-4" />
        <AlertTitle>Resposta gerada por IA</AlertTitle>
        <AlertDescription>
          Confira sempre o SQL gerado (botão de detalhes na resposta) antes de levar um número
          para a reunião — é o que separa quem usa Genie de quem confia em Genie.
        </AlertDescription>
      </Alert>

      <div style={{ height: 600 }} className="border rounded-lg overflow-hidden">
        <GenieChat alias="default" />
      </div>
    </div>
  );
}
