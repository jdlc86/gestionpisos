alter table public.photo_verification_items_v2 add constraint photo_verification_items_v2_alignment_meta_check check (alignment_meta is null or jsonb_typeof(alignment_meta) = 'object');
