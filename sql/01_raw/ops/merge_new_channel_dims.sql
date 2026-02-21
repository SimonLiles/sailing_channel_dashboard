MERGE INTO channel_dimensions as target
  USING channel_dimensions_staging as source
  ON target.id = source.id
WHEN MATCHED THEN
  UPDATE SET 
    target.handle = source.handle, 
    target.title = source.title,
    target.description = source.description,
    target.join_date = source.join_date
WHEN NOT MATCHED BY TARGET THEN
  INSERT (handle, title, description, join_date) 
    VALUES (source.handle, source.title, source.description, source.join_date);