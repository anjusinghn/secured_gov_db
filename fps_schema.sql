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

CREATE TABLE master.enforcement_solutions_pedestrian_animal_crossing (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_pedestrian_animal_crossing OWNER TO postgres;

--
-- Name: enforcement_solutions_rash_driving; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_rash_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_rash_driving OWNER TO postgres;

--
-- Name: enforcement_solutions_self_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_self_accidents OWNER TO postgres;

--
-- Name: enforcement_solutions_small_t_junction_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_small_t_junction_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_small_t_junction_accidents OWNER TO postgres;

--
-- Name: enforcement_solutions_vehicles_overspeeding; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_vehicles_overspeeding (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_vehicles_overspeeding OWNER TO postgres;

--
-- Name: enforcement_solutions_wrong_way_driving; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.enforcement_solutions_wrong_way_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.enforcement_solutions_wrong_way_driving OWNER TO postgres;

--
-- Name: formation_of_junction; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.formation_of_junction (
    english character varying,
    hindi character varying,
    odia character varying,
    id character varying
);


ALTER TABLE master.formation_of_junction OWNER TO postgres;

--
-- Name: has_caused_accident_at_spot; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.has_caused_accident_at_spot (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.has_caused_accident_at_spot OWNER TO postgres;

--
-- Name: interventions; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.interventions (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.interventions OWNER TO postgres;

--
-- Name: landmark_type; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.landmark_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.landmark_type OWNER TO postgres;

--
-- Name: landuse_pattern; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.landuse_pattern (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.landuse_pattern OWNER TO postgres;

--
-- Name: light_availability; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.light_availability (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.light_availability OWNER TO postgres;

--
-- Name: major_reasons_for_self_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.major_reasons_for_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.major_reasons_for_self_accidents OWNER TO postgres;

--
-- Name: master_data; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.master_data (
    id character varying,
    type character varying,
    page_name character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.master_data OWNER TO postgres;

--
-- Name: no_of_lanes; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.no_of_lanes (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.no_of_lanes OWNER TO postgres;

--
-- Name: parked_vehicle_accidents_reasons; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.parked_vehicle_accidents_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.parked_vehicle_accidents_reasons OWNER TO postgres;

--
-- Name: pattern_of_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.pattern_of_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.pattern_of_accidents OWNER TO postgres;

--
-- Name: pedestrain_animal_crossing_the_spot_reasons; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.pedestrain_animal_crossing_the_spot_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.pedestrain_animal_crossing_the_spot_reasons OWNER TO postgres;

--
-- Name: prevalent_vehicle_type; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.prevalent_vehicle_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.prevalent_vehicle_type OWNER TO postgres;

--
-- Name: rash_drivers; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.rash_drivers (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.rash_drivers OWNER TO postgres;

--
-- Name: reason_for_visibility_obstruction; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.reason_for_visibility_obstruction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.reason_for_visibility_obstruction OWNER TO postgres;

--
-- Name: reasons_for_vehicles_not_slowing_down; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.reasons_for_vehicles_not_slowing_down (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.reasons_for_vehicles_not_slowing_down OWNER TO postgres;

--
-- Name: road_engineering_solutions_parked_vehicle_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_parked_vehicle_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_parked_vehicle_accidents OWNER TO postgres;

--
-- Name: road_engineering_solutions_pedestrain_animal_crossing; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_pedestrain_animal_crossing (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_pedestrain_animal_crossing OWNER TO postgres;

--
-- Name: road_engineering_solutions_road_condition; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_road_condition (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_road_condition OWNER TO postgres;

--
-- Name: road_engineering_solutions_self_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_self_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_self_accidents OWNER TO postgres;

--
-- Name: road_engineering_solutions_small_t_junction_accidents; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_small_t_junction_accidents (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_small_t_junction_accidents OWNER TO postgres;

--
-- Name: road_engineering_solutions_vehicles_overspeeding; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_vehicles_overspeeding (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_vehicles_overspeeding OWNER TO postgres;

--
-- Name: road_engineering_solutions_wrong_way_driving; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_solutions_wrong_way_driving (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_solutions_wrong_way_driving OWNER TO postgres;

--
-- Name: road_engineering_suggestions_to_avoid_the_accident_visibility; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_engineering_suggestions_to_avoid_the_accident_visibility (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_engineering_suggestions_to_avoid_the_accident_visibility OWNER TO postgres;

--
-- Name: road_user_vio; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_user_vio (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_user_vio OWNER TO postgres;

--
-- Name: road_user_violations_causing_accidents_junction; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_user_violations_causing_accidents_junction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_user_violations_causing_accidents_junction OWNER TO postgres;

--
-- Name: road_user_violations_causing_accidents_stretch; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.road_user_violations_causing_accidents_stretch (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.road_user_violations_causing_accidents_stretch OWNER TO postgres;

--
-- Name: status_field_inspection; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.status_field_inspection (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.status_field_inspection OWNER TO postgres;

--
-- Name: status_of_approval; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.status_of_approval (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.status_of_approval OWNER TO postgres;
