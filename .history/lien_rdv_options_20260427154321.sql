-- Jointure entre les RDV Web (Novius) et les Options (Winner)
-- sur Email OU Téléphone, dans une fenêtre de 6 mois avant la commande.
-- On ne garde que le 1er RDV (le plus ancien) par option/magasin.
-- Export du résultat en CSV.


COPY (
    SELECT
        REFERENCE_DE_L_OPTION,
        DATE_PREMIER_DEVIS,
        DATE_PREMIERE_COMMANDE,
        CA_CDE_HTHPL,
        MONTANT_CREDIT_ACCEPTE,
        IFNULL(E_MAIL, EMAIL)   AS EMAIL,
        NOM_DU_FICHIER          AS MAG_ID,
        ID_RDV,
        DATE_RDV
    FROM (
        SELECT
            opt.DATE_PREMIERE_COMMANDE,
            opt.DATE_PREMIER_DEVIS,
            opt.MONTANT_CREDIT_ACCEPTE,
            opt.CA_CDE_HTHPL,
            opt.NOM_DU_FICHIER,
            opt.REFERENCE_DE_L_OPTION,
            opt.E_MAIL,
            opt.TELEPHONE1,
            rdv.ID_RDV,
            rdv.DATE1       AS DATE_RDV,
            rdv.EMAIL,
            rdv.PHONE,
            -- Rang du RDV : le plus ancien en premier, par option/magasin
            RANK() OVER (
                PARTITION BY opt.NOM_DU_FICHIER, opt.REFERENCE_DE_L_OPTION
                ORDER BY rdv.DATE1 ASC
            ) AS RANG_RDV
        FROM (
            SELECT
                NOM_DU_FICHIER,
                DATE_PREMIERE_COMMANDE,
                DATE_PREMIER_DEVIS,
                MONTANT_CREDIT_ACCEPTE,
                CA_CDE_HTHPL,
                E_MAIL,
                TELEPHONE1,
                REFERENCE_DE_L_OPTION
            FROM memory.TEC_WINNER_CA_TOTAL_OPTION
            WHERE DATE_PREMIER_DEVIS >= '2025-01-01'
        ) opt
        LEFT OUTER JOIN (
            SELECT
                ID_RDV,
                DATE1,
                PHONE,
                EMAIL
            FROM memory.DWH_NOVIUS_RDV
            WHERE DATE1 >= '2025-01-01'
        ) rdv
            ON (
                -- Lien sur email OU téléphone normalisé
                (opt.E_MAIL = rdv.EMAIL OR rdv.PHONE = opt.TELEPHONE1)
                -- Le RDV doit être antérieur ou le jour même de la commande
                AND rdv.DATE1 <= opt.DATE_PREMIERE_COMMANDE
                -- ... et dans une fenêtre de 6 mois maximum
                AND rdv.DATE1 >= DATE_ADD(opt.DATE_PREMIERE_COMMANDE, -INTERVAL '6 months')
            )
    )
    WHERE RANG_RDV = 1
)
TO '{{CSV_OUTPUT_PATH}}'
WITH (HEADER, DELIMITER ',', QUOTE '"');