const SUPABASE_URL = 'https://qrkuwndtznqwjogmnooc.supabase.co';
const SUPABASE_ANON_KEY='eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFya3V3bmR0em5xd2pvZ21ub29jIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODU0OTYzOTMsImV4cCI6MjEwMTA3MjM5M30.Ta579iT2cLl6O041a4TRZ6munD6fUjs-O48yFR4MIcE';
const { createClient } = window.supabase;
const db = createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
