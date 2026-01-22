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

--
-- Name: status_of_estimate; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.status_of_estimate (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.status_of_estimate OWNER TO postgres;

--
-- Name: status_of_implementation; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.status_of_implementation (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.status_of_implementation OWNER TO postgres;

--
-- Name: stretch_shape; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.stretch_shape (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.stretch_shape OWNER TO postgres;

--
-- Name: stretch_type; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.stretch_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.stretch_type OWNER TO postgres;

--
-- Name: switching_type; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.switching_type (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.switching_type OWNER TO postgres;

--
-- Name: type_of_junction; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.type_of_junction (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.type_of_junction OWNER TO postgres;

--
-- Name: wrong_way_driving_reasons; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.wrong_way_driving_reasons (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.wrong_way_driving_reasons OWNER TO postgres;

--
-- Name: yes_no_dropdowns; Type: TABLE; Schema: master; Owner: postgres
--

CREATE TABLE master.yes_no_dropdowns (
    id character varying,
    english character varying,
    hindi character varying,
    odia character varying
);


ALTER TABLE master.yes_no_dropdowns OWNER TO postgres;

--
-- Name: fsa_acc; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_acc (
    detail_id bigint NOT NULL,
    acc_pattern_onspot character varying,
    no_of_injuries integer,
    no_of_deaths integer,
    no_of_accidents character varying,
    nearest_hosp character varying,
    acc_id character varying NOT NULL,
    start_age_range integer,
    end_age_range integer,
    age_range character varying,
    time_frame_acc character varying,
    edited boolean DEFAULT false
);


ALTER TABLE public.fsa_acc OWNER TO postgres;

--
-- Name: fsa_admin_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_admin_table (
    admin_email character varying NOT NULL,
    admin_id bigint NOT NULL,
    admin_role_id bigint,
    admin_role character varying,
    admin_name character varying,
    admin_pwd character varying,
    login_status boolean,
    last_login character varying,
    user_status boolean,
    state_name character varying,
    district_name character varying,
    state_code character varying,
    district_code character varying,
    created_by character varying,
    phone_no character varying
);


ALTER TABLE public.fsa_admin_table OWNER TO postgres;

--
-- Name: fsa_admin_table_admin_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.fsa_admin_table ALTER COLUMN admin_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.fsa_admin_table_admin_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fsa_light; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_light (
    light_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    light_avail character varying,
    switch_type character varying,
    non_avail_light character varying,
    light_photos jsonb,
    edited boolean DEFAULT false,
    delete_status boolean
);


ALTER TABLE public.fsa_light OWNER TO postgres;

--
-- Name: fsa_onspot; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_onspot (
    detail_id bigint NOT NULL,
    onspot_id character varying NOT NULL,
    lat double precision,
    long double precision,
    highway_no character varying,
    land_use_pattern character varying,
    hotspot_type character varying,
    junction_type character varying,
    junction_name character varying,
    junction_formation character varying,
    stretch_type character varying,
    stretch_shape character varying,
    no_of_lanes character varying,
    median_presence character varying,
    median_opening character varying,
    speed_of_all_vehicles character varying,
    adjoining_or_junction_no character varying,
    landmark_name character varying,
    landmark_type character varying,
    landmark_dist character varying,
    onspot_images jsonb,
    landmark_type_other character varying,
    edited boolean DEFAULT false,
    junction_formation_others character varying,
    no_of_lanes_others character varying,
    name_of_stretch character varying,
    delete_status boolean
);


ALTER TABLE public.fsa_onspot OWNER TO postgres;

--
-- Name: fsa_ped_cross; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_ped_cross (
    ped_self_park_t_rash_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    ped_animal_cross_lead_acc character varying,
    ped_animal_cross_spot_reason character varying,
    road_eng_sol_ped_ani character varying,
    enforce_sol_ped_ani character varying,
    self_acc_in_junc_freq character varying,
    major_reason_self_acc character varying,
    road_eng_sol_self_acc character varying,
    enf_sol_self_acc character varying,
    acc_hitting_parked_veh character varying,
    parked_veh_acc_reason character varying,
    road_eng_sol_parked_veh_acc character varying,
    enforce_sol_parked_veh_acc character varying,
    acc_due_small_t_join_roads character varying,
    veh_slow_down_small_t_or_join_roads character varying,
    acc_due_small_t_join_roads_reason character varying,
    road_eng_sol_for_small_t_join_roads character varying,
    enforce_sol_for_small_t_join_roads character varying,
    rash_drivers character varying,
    enforce_sol_rash_drive character varying,
    remarks character varying,
    types_of_rash_drivers character varying,
    others_major_reason_self_acc character varying,
    others_road_eng_sol_self_acc character varying,
    types_of_rash_drivers_others character varying,
    enforce_sol_rash_drive_others character varying,
    enforce_sol_ped_ani_others character varying,
    ped_animal_cross_spot_reason_others character varying,
    road_eng_sol_ped_ani_others character varying,
    enf_sol_self_acc_others character varying,
    enforce_sol_parked_veh_acc_others character varying,
    parked_veh_acc_reason_others character varying,
    road_eng_sol_parked_veh_acc_others character varying,
    acc_due_small_t_join_roads_reason_others character varying,
    enforce_sol_for_small_t_join_roads_others character varying,
    road_eng_sol_for_small_t_join_roads_others character varying,
    edited boolean DEFAULT false,
    delete_status boolean
);


ALTER TABLE public.fsa_ped_cross OWNER TO postgres;

--
-- Name: fsa_roadcnd; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_roadcnd (
    roadcnd_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    road_issue character varying,
    road_defects character varying,
    road_photos jsonb,
    road_eng_sol_roadcnd character varying,
    road_defects_others character varying,
    road_eng_sol_rdcnd_others character varying,
    delete_status boolean
);


ALTER TABLE public.fsa_roadcnd OWNER TO postgres;

--
-- Name: fsa_state_district_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_state_district_table (
    state_admin_id bigint,
    state_admin_name character varying,
    state_code character varying,
    district_admin_id bigint,
    district_admin_name character varying,
    district_code character varying,
    state_roa_id bigint,
    state_roa_name character varying,
    roa_state_code character varying[],
    roa_district_code character varying[],
    district_roa_id bigint,
    district_roa_name character varying,
    multiple_districts text[]
);


ALTER TABLE public.fsa_state_district_table OWNER TO postgres;

--
-- Name: fsa_traff_status; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_traff_status (
    detail_id bigint NOT NULL,
    traff_status_id character varying NOT NULL,
    signal_avail character varying,
    signal_visible character varying,
    signal_working character varying,
    signal_timer_work character varying,
    signal_need character varying,
    signal_photos jsonb,
    signboards_avail character varying,
    signboards_visible character varying,
    signboards_photos jsonb,
    road_markings_avail character varying,
    road_markings_photos jsonb,
    edited boolean DEFAULT false,
    delete_status boolean
);


ALTER TABLE public.fsa_traff_status OWNER TO postgres;

--
-- Name: fsa_traffic_condt; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_traffic_condt (
    traffic_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    prevalent_veh_type character varying,
    start_time character varying,
    end_time character varying,
    delete_status boolean
);


ALTER TABLE public.fsa_traffic_condt OWNER TO postgres;

--
-- Name: fsa_user_id; Type: SEQUENCE; Schema: public; Owner: postgres
--

CREATE SEQUENCE public.fsa_user_id
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


ALTER SEQUENCE public.fsa_user_id OWNER TO postgres;

--
-- Name: fsa_user_roles; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_user_roles (
    user_type character varying NOT NULL,
    user_role character varying
);


ALTER TABLE public.fsa_user_roles OWNER TO postgres;

--
-- Name: fsa_user_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_user_table (
    pwd character varying NOT NULL,
    last_login character varying,
    login_status boolean,
    email character varying NOT NULL,
    rep_name character varying,
    designation character varying,
    department character varying,
    phone_no character varying,
    userid bigint DEFAULT nextval('public.fsa_user_id'::regclass) NOT NULL,
    user_type character varying,
    user_role character varying,
    terms_cond boolean,
    user_file jsonb,
    admin_id bigint,
    user_status boolean,
    state_code character varying,
    district_code character varying,
    state_name character varying,
    district_name character varying,
    ps_code character varying,
    police_station character varying
);


ALTER TABLE public.fsa_user_table OWNER TO postgres;

--
-- Name: fsa_user_table_bak; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_user_table_bak (
    pwd character varying,
    last_login character varying,
    login_status boolean,
    email character varying,
    rep_name character varying,
    designation character varying,
    department character varying,
    phone_no character varying,
    userid bigint,
    user_type character varying,
    user_role character varying,
    terms_cond boolean,
    user_file jsonb,
    admin_id bigint,
    user_status boolean,
    state_code character varying,
    district_code character varying,
    state_name character varying,
    district_name character varying
);


ALTER TABLE public.fsa_user_table_bak OWNER TO postgres;

--
-- Name: fsa_violations; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_violations (
    violations_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    road_user_vio_cause_acc character varying,
    overspeeding_onspot character varying,
    avg_speed_range character varying,
    m2w character varying,
    lmv character varying,
    hmv character varying,
    reason_for_not_slowing character varying,
    road_eng_sol_vehoverspeed character varying,
    enf_sol_veh_over_speed character varying,
    others_road_user_vio_cause_acc character varying,
    reason_for_not_slowing_others character varying,
    enf_sol_veh_over_speed_others character varying,
    road_eng_sol_vehoverspeed_others character varying,
    edited boolean DEFAULT false,
    delete_status boolean
);


ALTER TABLE public.fsa_violations OWNER TO postgres;

--
-- Name: fsa_visible; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_visible (
    detail_id bigint NOT NULL,
    visible_id character varying NOT NULL,
    visib_obstruct_by_objs character varying,
    atspot_accident_cause character varying,
    road_eng_sol character varying,
    visib_photos jsonb,
    is_visib_obstructed character varying,
    is_visib_obstructed_others character varying,
    road_eng_sol_others character varying,
    delete_status boolean
);


ALTER TABLE public.fsa_visible OWNER TO postgres;

--
-- Name: fsa_wrngway; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.fsa_wrngway (
    wrgnway_id character varying NOT NULL,
    detail_id bigint NOT NULL,
    veh_wrngway_roadside_junct character varying,
    wrgnway_driving_reason character varying,
    nearest_opening_to_cross character varying,
    road_engg_sol_for_wrngway character varying,
    enforce_sol_for_wrngway character varying,
    overtaking_acc character varying,
    median_avail character varying,
    space_to_overtake character varying,
    enforce_sol_for_wrngway_other character varying,
    road_engg_sol_for_wrngway_others character varying,
    wrgnway_driving_reason_others character varying,
    reason_for_not_slowing_others character varying,
    edited boolean DEFAULT false,
    delete_status boolean
);


ALTER TABLE public.fsa_wrngway OWNER TO postgres;

--
-- Name: gen_details; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.gen_details (
    detail_id bigint NOT NULL,
    rep_name jsonb,
    designation jsonb,
    department jsonb,
    phone_no jsonb,
    email jsonb,
    userid bigint NOT NULL,
    state jsonb,
    district jsonb,
    state_code jsonb,
    district_code jsonb,
    edited boolean DEFAULT false,
    start_date character varying,
    end_date character varying,
    delete_status boolean,
    police_station character varying,
    ps_code character varying
);


ALTER TABLE public.gen_details OWNER TO postgres;

--
-- Name: gen_details_detail_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.gen_details ALTER COLUMN detail_id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.gen_details_detail_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: intervention; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.intervention (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying,
    uploaded_docs character varying
);


ALTER TABLE public.intervention OWNER TO postgres;

--
-- Name: intervention_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.intervention ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.intervention_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: master_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.master_table (
    type_of_junction character varying,
    formation_of_junction character varying,
    stretch_type character varying,
    stretch_shape character varying,
    no_of_lanes character varying,
    landmark_type character varying,
    prevalent_vehicle_type character varying,
    reason_for_visibility_obstruction character varying,
    road_engineering_suggestions_to_avoid_the_accident_visibility character varying,
    defects character varying,
    road_engineering_solutions_road_condition character varying,
    pattern_of_accidents character varying,
    road_user_violations_causing_accidents character varying,
    reasons_for_vehicles_not_slowing_down character varying,
    road_engineering_solutions_vehicles_overspeeding character varying,
    enforcement_solutions_vehicles_overspeeding character varying,
    wrong_way_driving_reasons character varying,
    road_engineering_solutions_wrong_way_driving character varying,
    enforcement_solutions_wrong_way_driving character varying,
    pedestrain_animal_crossing_the_spot_reasons character varying,
    road_engineering_solutions_pedestrain_animal_crossing character varying,
    enforcement_solutions_pedestrian_animal_crossing character varying,
    major_reasons_for_self_accidents character varying,
    road_engineering_solutions_self_accidents character varying,
    enforcement_solutions_self_accidents character varying,
    parked_vehicle_accidents_reasons character varying,
    road_engineering_solutions_parked_vehicle_accidents character varying,
    enforcement_solutions_parked_vehicle_accidents character varying,
    accidents_due_to_small_t_junction_accidents_or_nearby_joining_r character varying,
    road_engineering_solutions_small_t_junction_accidents character varying,
    enforcement_solutions_small_t_junction_accidents character varying,
    rash_drivers character varying,
    enforcement_solutions_rash_driving character varying,
    age_range character varying(255)
);


ALTER TABLE public.master_table OWNER TO postgres;

--
-- Name: remarks_by_engg; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.remarks_by_engg (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying
);


ALTER TABLE public.remarks_by_engg OWNER TO postgres;

--
-- Name: remarks_by_engg_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.remarks_by_engg ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.remarks_by_engg_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: stages_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.stages_table (
    id bigint NOT NULL,
    detail_id bigint NOT NULL,
    status_field_inspection character varying,
    intervention character varying,
    status_of_estimate character varying,
    status_of_approval character varying,
    status_of_implementation character varying,
    remarks_by_engg character varying,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying,
    upload_docs_intervention character varying,
    upload_docs_estimation character varying
);


ALTER TABLE public.stages_table OWNER TO postgres;

--
-- Name: stages_table_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.stages_table ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.stages_table_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: state_district_master_table; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.state_district_master_table (
    state_name character varying,
    district_name character varying,
    state_code character varying,
    district_code character varying,
    s_no bigint
);


ALTER TABLE public.state_district_master_table OWNER TO postgres;

--
-- Name: status_field_inspection; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status_field_inspection (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying
);


ALTER TABLE public.status_field_inspection OWNER TO postgres;

--
-- Name: status_field_inspection_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.status_field_inspection ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_field_inspection_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: status_of_approval; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status_of_approval (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying
);


ALTER TABLE public.status_of_approval OWNER TO postgres;

--
-- Name: status_of_approval_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.status_of_approval ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_approval_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: status_of_estimate; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status_of_estimate (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying,
    uploaded_docs character varying
);


ALTER TABLE public.status_of_estimate OWNER TO postgres;

--
-- Name: status_of_estimate_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.status_of_estimate ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_estimate_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: status_of_implementation; Type: TABLE; Schema: public; Owner: postgres
--

CREATE TABLE public.status_of_implementation (
    id bigint NOT NULL,
    detail_id bigint,
    time_updated character varying,
    admin_name character varying,
    admin_role character varying,
    admin_email character varying,
    admin_id character varying
);


ALTER TABLE public.status_of_implementation OWNER TO postgres;

--
-- Name: status_of_implementation_id_seq; Type: SEQUENCE; Schema: public; Owner: postgres
--

ALTER TABLE public.status_of_implementation ALTER COLUMN id ADD GENERATED ALWAYS AS IDENTITY (
    SEQUENCE NAME public.status_of_implementation_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1
);


--
-- Name: fsa_acc acc_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT acc_pkey PRIMARY KEY (acc_id);


--
-- Name: fsa_admin_table admin_email; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_admin_table
    ADD CONSTRAINT admin_email UNIQUE (admin_email);


--
-- Name: fsa_user_table email; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_user_table
    ADD CONSTRAINT email UNIQUE (email);


--
-- Name: gen_details fsa_details_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.gen_details
    ADD CONSTRAINT fsa_details_pkey PRIMARY KEY (detail_id);


--
-- Name: fsa_light fsa_light_visib_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_visib_pkey PRIMARY KEY (light_id);


--
-- Name: fsa_onspot fsa_onspot_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_onspot
    ADD CONSTRAINT fsa_onspot_pkey PRIMARY KEY (onspot_id);


--
-- Name: fsa_ped_cross fsa_ped_self_park_t_rash_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_ped_cross
    ADD CONSTRAINT fsa_ped_self_park_t_rash_pkey PRIMARY KEY (ped_self_park_t_rash_id);


--
-- Name: fsa_traff_status fsa_traff_status_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_traff_status
    ADD CONSTRAINT fsa_traff_status_pkey PRIMARY KEY (traff_status_id);


--
-- Name: fsa_traffic_condt fsa_traffic_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_traffic_condt
    ADD CONSTRAINT fsa_traffic_pkey PRIMARY KEY (traffic_id);


--
-- Name: fsa_user_roles fsa_user_roles_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_user_roles
    ADD CONSTRAINT fsa_user_roles_pkey PRIMARY KEY (user_type);


--
-- Name: fsa_user_table fsa_user_table_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_user_table
    ADD CONSTRAINT fsa_user_table_pkey PRIMARY KEY (userid);


--
-- Name: fsa_violations fsa_violations_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_violations
    ADD CONSTRAINT fsa_violations_pkey PRIMARY KEY (violations_id);


--
-- Name: fsa_visible fsa_visible_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_visible
    ADD CONSTRAINT fsa_visible_pkey PRIMARY KEY (visible_id);


--
-- Name: fsa_wrngway fsa_wrngway_overtake_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_wrngway
    ADD CONSTRAINT fsa_wrngway_overtake_pkey PRIMARY KEY (wrgnway_id);


--
-- Name: stages_table stages_table_pkey; Type: CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.stages_table
    ADD CONSTRAINT stages_table_pkey PRIMARY KEY (detail_id);


--
-- Name: fsa_acc detail_id; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_acc
    ADD CONSTRAINT detail_id FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;


--
-- Name: fsa_light fsa_light_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_light
    ADD CONSTRAINT fsa_light_detail_id_fkey FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;


--
-- Name: fsa_onspot fsa_onspot_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_onspot
    ADD CONSTRAINT fsa_onspot_detail_id_fkey FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;


--
-- Name: fsa_ped_cross fsa_ped_cross_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_ped_cross
    ADD CONSTRAINT fsa_ped_cross_detail_id_fkey FOREIGN KEY (detail_id) REFERENCES public.gen_details(detail_id) NOT VALID;


--
-- Name: fsa_roadcnd fsa_roadcnd_detail_id_fkey; Type: FK CONSTRAINT; Schema: public; Owner: postgres
--

ALTER TABLE ONLY public.fsa_roadcnd
