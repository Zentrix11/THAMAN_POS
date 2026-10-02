# Migration 006 required

Run `supabase/migrations/006_offers_and_subscription_requests.sql` once in the same Supabase project after migrations 001–005.

This migration adds subscriber-facing plan/offer fields, the subscription request queue, POS catalog/request RPCs and owner-only Admin request controls.
