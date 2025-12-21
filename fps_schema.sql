--
-- PostgreSQL database dump
--

\restrict IwEwdQqfDDfkz2F9uQas9IkfWR64M3A7cuaWN3weNs4NKVeUpsgFbcqWnGKwJlD

-- Dumped from database version 16.11 (Ubuntu 16.11-0ubuntu0.24.04.1)
-- Dumped by pg_dump version 16.11 (Ubuntu 16.11-0ubuntu0.24.04.1)

SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'SQL_ASCII';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: master; Type: SCHEMA; Schema: -; Owner: postgres
--

CREATE SCHEMA master;


ALTER SCHEMA master OWNER TO postgres;

--
-- Name: fetch_data_from_tables(integer); Type: FUNCTION; Schema: public; Owner: postgres
--

CREATE FUNCTION public.fetch_data_from_tables(adm_id integer) RETURNS TABLE(state_val text, district_val text)
    LANGUAGE plpgsql
    AS $$
                    DECLARE
                        role_id TEXT;
                        the_role TEXT;
                    BEGIN
                        SELECT admin_role_id INTO role_id FROM fsa_admin_table WHERE admin_id = adm_id;
                        SELECT user_role INTO the_role FROM fsa_user_roles WHERE user_type = role_id;

                        IF the_role = 'State Admin' THEN
                           	RETURN QUERY   
							SELECT DISTINCT
								   s.state_name::text  AS state_val,
								   d.district_name::text AS district_val
							FROM fsa_state_district_table fsd
							  JOIN (
								SELECT DISTINCT state_code, state_name
								FROM state_district_master_table
							  ) s
								ON s.state_code = fsd.state_code
							  LEFT JOIN state_district_master_table d
								ON d.state_code    = fsd.state_code
							   AND d.district_code = NULLIF(fsd.district_code, '')
							WHERE fsd.state_admin_id = adm_id;
