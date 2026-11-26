export function TxStatus({ status, error }: { status: string | null; error: string | null }) {
  if (error) return <p style={{ color: "crimson" }}>{error}</p>;
  if (status) return <p>{status}</p>;
  return null;
}