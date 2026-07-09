-- Charge les données sources depuis SQL Server dans la mémoire DuckDB
-- via l'extension nanodbc (ODBC)
-- Installation et chargement de l'extension nanodbc (connexion ODBC)
INSTALL nanodbc FROM community;
LOAD nanodbc;

-- TABLE 1 : Options Winner (devis / commandes)

CREATE OR REPLACE TABLE memory.TEC_WINNER_CA_TOTAL_OPTION AS
SELECT
    NOM_DU_FICHIER,
    DATE_PREMIERE_COMMANDE::DATE   AS DATE_PREMIERE_COMMANDE,
    DATE_PREMIER_DEVIS::DATE       AS DATE_PREMIER_DEVIS,
    MONTANT_CREDIT_ACCEPTE::FLOAT  AS MONTANT_CREDIT_ACCEPTE,
    CA_CDE_HTHPL::FLOAT           AS CA_CDE_HTHPL,
    E_MAIL,
    TELEPHONE1,
    REFERENCE_DE_L_OPTION
FROM odbc_query(
    connection = 'Driver={SQL Server};Server=050-VLB-SRV-MYREPORT;Database=DWH_MyBI;UID=sa;PWD=AvivA#sql;',
    query = "SELECT
        NOM_DU_FICHIER,
        DATE_PREMIERE_COMMANDE,
        DATE_PREMIER_DEVIS,
        MONTANT_CREDIT_ACCEPTE,
        CA_CDE_HTHPL,
        E_MAIL,
        TELEPHONE1,
        REFERENCE_DE_L_OPTION
    FROM TEC_WINNER_CA_TOTAL_OPTION"
);

-- TABLE 2 : Rendez-vous Web Novius

CREATE OR REPLACE TABLE memory.DWH_NOVIUS_RDV AS
SELECT
    ID_RDV::INT   AS ID_RDV,
    DATE1::DATE    AS DATE1,
    PHONE,
    EMAIL
FROM odbc_query(
    connection = 'Driver={SQL Server};Server=050-VLB-SRV-MYREPORT;Database=DWH_MyBI;UID=sa;PWD=AvivA#sql;',
    query = "SELECT
        ID_RDV,
        DATE1,
        PHONE,
        EMAIL
    FROM DWH_NOVIUS_RDV"
);