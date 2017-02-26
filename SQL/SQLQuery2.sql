/* 
 リソース クラスの変更 
 */
-- ログイン作成(Master DBで実行）
 CREATE LOGIN newperson WITH PASSWORD = 'P@ssw0rd';

-- リソースクラスが指定されていないため規定値のsmallrc
SELECT  r.name AS role_principal_name
        ,m.name AS member_principal_name
FROM    sys.database_role_members rm
JOIN    sys.database_principals AS r ON rm.role_principal_id = r.principal_id
JOIN    sys.database_principals AS m ON rm.member_principal_id = m.principal_id
WHERE    r.name IN ('smallrc', 'mediumrc','largerc', 'xlargerc');

-- ユーザーを作成する(DB)
 CREATE USER newperson FOR LOGIN newperson;

-- アクセス許可を付与する
 GRANT CONTROL ON DATABASE::sqldwdb to newperson;

-- リソース クラスのサイズを変更
 EXEC sp_addrolemember 'largerc', 'newperson'

-- リソース クラスの確認
SELECT  r.name AS role_principal_name
        ,m.name AS member_principal_name
FROM    sys.database_role_members rm
JOIN    sys.database_principals AS r ON rm.role_principal_id = r.principal_id
JOIN    sys.database_principals AS m ON rm.member_principal_id = m.principal_id
WHERE    r.name IN ('smallrc', 'mediumrc','largerc', 'xlargerc');

-- 削除処理
 EXEC sp_droprolemember 'largerc', 'newperson';
 DROP USER newperson
 DROP LOGIN newperson




/* 
 データの偏り 
 */
-- ハッシュキー列のデータの種類
SELECT COUNT(DISTINCT SalesOrderNumber) AS FactInternetSalesReasonNum FROM FactInternetSalesReason
SELECT COUNT(DISTINCT CurrencyKey) AS CurrencyKeyNum FROM FactCurrencyRate

-- データの種類が多いテーブル（カーディナリティが高い）
DBCC PDW_SHOWSPACEUSED(FactInternetSalesReason)

-- データの種類が少ないテーブル（カーディナリティが低い）
DBCC PDW_SHOWSPACEUSED(FactCurrencyRate)

-- データの移動（ハッシュのキーと結合キー）
-- データの移動が発生しないパターン（ハッシュのキーが結合キー）
EXPLAIN SELECT COUNT(*) FROM FactInternetSales F INNER JOIN DimProduct P ON F.ProductKey = P.ProductKey

-- ラウンドロビンでテーブルデータをコピー
IF OBJECT_ID('dbo.FactInternetSales_ROUND_ROBIN', 'U') IS NOT NULL
DROP TABLE dbo.FactInternetSales_ROUND_ROBIN 

CREATE TABLE dbo.FactInternetSales_ROUND_ROBIN 
WITH (  CLUSTERED COLUMNSTORE INDEX
            ,  DISTRIBUTION =  ROUND_ROBIN
  )
AS
SELECT  *
FROM    [dbo].[FactInternetSales]
OPTION  (LABEL  = 'CTAS : FactInternetSales_ROUND_ROBIN')
;

-- データの移動が発生するパターン（ハッシュのキーが結合キーでない）
EXPLAIN SELECT COUNT(*) FROM FactInternetSales_ROUND_ROBIN F INNER JOIN DimProduct P ON F.ProductKey = P.ProductKey

-- テーブルの分散を確認
DBCC PDW_SHOWSPACEUSED('dbo.FactInternetSales');

-- テーブルに割り当てられているDistributionの確認
select OBJECT_NAME(object_id),* from sys.pdw_table_mappings where object_id = OBJECT_ID('dbo.FactInternetSales')
select OBJECT_NAME(object_id),COUNT(*) from sys.pdw_table_mappings where object_id = OBJECT_ID('dbo.FactInternetSales') GROUP BY object_id




/* 
 テーブル定義 
 */
-- ラウンドロビンテーブル作成
CREATE TABLE [dbo].[FactInternetSales_ROUND_ROBIN] 
WITH (  CLUSTERED COLUMNSTORE INDEX
            ,  DISTRIBUTION =  ROUND_ROBIN
    )
AS
SELECT  *
FROM    [dbo].[FactInternetSales]
OPTION  (LABEL  = 'CTAS : FactInternetSales_ROUND_ROBIN')
;

--テーブル名の変更
RENAME OBJECT [dbo].[FactInternetSales] TO [FactInternetSales_ProductKey];
RENAME OBJECT [dbo].[FactInternetSales_CustomerKey] TO [FactInternetSales];

-- データの分散を確認（カーディナリティが高いテーブルと低いテーブル）
SELECT 
    s.name as schema_name, t.name AS table_name,
	tdp.distribution_policy_desc, c.name AS distribution_column
FROM sys.schemas s
INNER JOIN sys.tables t
    ON s.schema_id = t.schema_id
INNER JOIN sys.pdw_table_distribution_properties tdp
    ON t.object_id = tdp.object_id
LEFT OUTER JOIN (SELECT * FROM sys.pdw_column_distribution_properties
                 WHERE distribution_ordinal = 1) cdp
    ON tdp.object_id = cdp.object_id
LEFT OUTER JOIN sys.columns c
    ON cdp.object_id = c.object_id AND cdp.column_id = c.column_id
ORDER BY t.name;




/* 
 バックアップの確認
 */
select top 1 *
from sys.pdw_loader_backup_runs 
order by run_id desc;

