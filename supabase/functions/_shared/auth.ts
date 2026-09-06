import { createClient } from "npm:@supabase/supabase-js@^2";

export interface AuthedUser {
  id: string;
  name?: string;
}

/**
 * Valida o token de acesso do Supabase (JWT) enviado no header Authorization.
 * Retorna a identidade do usuário, ou null quando a requisição não é autenticada.
 */
export async function verifyUser(
  authHeader: string | null,
): Promise<AuthedUser | null> {
  if (!authHeader?.startsWith("Bearer ")) return null;
  const token = authHeader.slice("Bearer ".length).trim();
  if (!token) return null;

  const supabase = createClient(
    Deno.env.get("SUPABASE_URL") as string,
    Deno.env.get("SUPABASE_ANON_KEY") as string,
  );

  const { data, error } = await supabase.auth.getUser(token);
  if (error || !data?.user) return null;

  const meta = data.user.user_metadata ?? {};
  const name =
    typeof meta.full_name === "string"
      ? meta.full_name
      : typeof meta.name === "string"
        ? meta.name
        : undefined;

  return { id: data.user.id, name };
}