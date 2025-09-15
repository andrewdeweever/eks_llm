# resource "random_password" "rds_password" {
#   length  = 20
#   special = true
# }

# # RDS PostgreSQL Instance: For pgvector-enabled vector storage
# resource "aws_db_instance" "pgvector_rds" {
#   identifier              = replace("${var.project_name}-db", "-", "")
#   engine                  = "postgres"
#   engine_version          = "16.3"
#   instance_class          = "db.t3.medium"
#   allocated_storage       = 100
#   storage_type            = "gp3"
#   storage_encrypted       = true
#   kms_key_id              = null
#   db_name                 = "ragvectordb"
#   username                = "vectordbadmin"
#   password                = random_password.rds_password.result
#   parameter_group_name    = "default.postgres16"
#   db_subnet_group_name    = aws_db_subnet_group.rds_subnet_group.name
#   vpc_security_group_ids  = [aws_security_group.rds_sg.id]
#   publicly_accessible     = false
#   multi_az                = false
#   backup_retention_period = 7
#   skip_final_snapshot     = true
# }

# resource "postgresql_extension" "vector" {
#   name     = "vector"
#   database = aws_db_instance.pgvector_rds.db_name
# }
