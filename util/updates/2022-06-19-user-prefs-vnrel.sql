ALTER TABLE users_prefs ADD COLUMN vnrel_langs language[],
                        ADD COLUMN vnrel_olang boolean NOT NULL DEFAULT true,
                        ADD COLUMN vnrel_mtl   boolean NOT NULL DEFAULT false;

-- Attempt to infer vnrel_langs and vnrel_mtl from the old 'vnlang' column.
BEGIN;

CREATE OR REPLACE FUNCTION vnlang_to_langs(vnlang jsonb) RETURNS language[] AS $$
DECLARE
    ret language[];
    del language;
BEGIN
    ret := enum_range(null::language);
    FOR del IN SELECT key::language FROM jsonb_each(vnlang) x WHERE key NOT LIKE '%-mtl' AND value = 'false'
    LOOP
        ret := array_remove(ret, del);
    END LOOP;
    RETURN CASE WHEN array_length(ret,1) = array_length(enum_range(null::language),1) THEN NULL ELSE RET END;
END$$ LANGUAGE plpgsql;

WITH p(id,langs,mtl) AS (
    SELECT id, vnlang_to_langs(vnlang), vnlang->'en-mtl' is not distinct from 'true'
      FROM users_prefs WHERE vnlang IS NOT NULL
) UPDATE users_prefs
     SET vnrel_langs = langs, vnrel_mtl = mtl
    FROM p
   WHERE p.id = users_prefs.id AND (langs IS NOT NULL OR mtl);

DROP FUNCTION vnlang_to_langs(jsonb);

COMMIT;
