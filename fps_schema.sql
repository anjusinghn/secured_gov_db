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

                        ELSIF the_role = 'District Admin' THEN
                           	
							RETURN QUERY
							SELECT DISTINCT sdmt.state_name:: TEXT,sdmt.district_name ::TEXT
                            FROM fsa_state_district_table fsd INNER JOIN state_district_master_table sdmt
	                            ON fsd.state_code = sdmt.state_code AND 
								(fsd.district_code = sdmt.district_code OR fsd.district_code IS NULL) WHERE fsd.district_admin_id = adm_id;
							
                        ELSIF the_role = 'ROA_state_Admin' THEN
						
                           	RETURN QUERY
							SELECT
							    string_agg(DISTINCT sdmt.state_name, ',') AS state_names,
							    string_agg(DISTINCT sdmt.district_name, ',') AS district_names
							FROM fsa_state_district_table fsd
							CROSS JOIN LATERAL unnest(string_to_array(fsd.roa_state_code[1], ',')) AS s_code(state_code)
							LEFT JOIN LATERAL (
							    SELECT d_code.district_code
							    FROM unnest(string_to_array(fsd.roa_district_code[1], ',')) AS d_code(district_code)
							    WHERE d_code.district_code <> ''
							) d_code ON TRUE
							JOIN state_district_master_table sdmt
							    ON sdmt.state_code = s_code.state_code
							   AND (
							        d_code.district_code IS NULL
							        OR sdmt.district_code = d_code.district_code
							   )
							WHERE fsd.state_roa_id = adm_id;
							
                        ELSIF the_role = 'ROA_district_Admin' THEN
						
                            RETURN QUERY
	                        SELECT
							    string_agg(DISTINCT sdmt.state_name, ',') AS state_names,
							    string_agg(DISTINCT sdmt.district_name, ',') AS district_names
							FROM fsa_state_district_table fsd
							CROSS JOIN LATERAL unnest(string_to_array(fsd.roa_state_code[1], ',')) AS s_code(state_code)
							CROSS JOIN LATERAL unnest(string_to_array(fsd.roa_district_code[1], ',')) AS d_code(district_code)
							JOIN state_district_master_table sdmt
							    ON sdmt.state_code = s_code.state_code
							   AND sdmt.district_code = d_code.district_code
							WHERE fsd.district_roa_id = adm_id;
						ELSE
                            RETURN;  
                        END IF;
                    END;
                    $$;


ALTER FUNCTION public.fetch_data_from_tables(adm_id integer) OWNER TO postgres;

SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: accidents_due_to_small_t_junction_accidents_or_nearby_joining_r; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.accidents_due_to_small_t_junction_accidents_or_nearby_joining_r (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.accidents_due_to_small_t_junction_accidents_or_nearby_joining_r OWNER TO postgres;

--
-- Name: age_range; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.age_range (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.age_range OWNER TO postgres;

--
-- Name: defects; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.defects (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.defects OWNER TO postgres;

--
-- Name: enforcement_solutions_parked_vehicle_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_parked_vehicle_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_parked_vehicle_accidents OWNER TO postgres;

--
-- Name: enforcement_solutions_pedestrian_animal_crossing; Type: TABLE; Schema: master; Owner: postgres
--
