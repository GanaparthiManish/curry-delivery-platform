SELECT 
    tgname AS trigger_name,
    proname AS function_name,
    tgenabled AS enabled
FROM pg_trigger
JOIN pg_proc ON pg_proc.oid = pg_trigger.tgfoid
WHERE tgrelid = 'public.orders'::regclass OR tgrelid = 'public.notifications'::regclass;
