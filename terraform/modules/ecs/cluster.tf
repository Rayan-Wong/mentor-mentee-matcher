resource "aws_ecs_cluster" "app" {
  name = var.ecs_cluster_name

  tags = merge(
    var.tags,
    {
      Name = "${var.env}-${var.app_name}-cluster"
      Tier = "compute"
    }
  )
}
