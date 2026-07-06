// ── Replace with your Supabase project details ────────────
const SUPABASE_URL = 'https://xkwrahcccckmrgiqrhoe.supabase.co';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Inhrd3JhaGNjY2NrbXJnaXFyaG9lIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzcyODk2OTAsImV4cCI6MjA5Mjg2NTY5MH0.IapomfS37BK4KYUgWqfMz2DA8V1_utcFTJl8pU3fUQQ';
// ─────────────────────────────────────────────────────────

const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
