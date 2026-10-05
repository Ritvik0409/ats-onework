from fastapi import APIRouter
from typing import List
from app.projects.schemas import ProjectCreate, ProjectUpdate, ProjectMembersUpdate

router = APIRouter(prefix="/projects", tags=["Projects"])

@router.get("")
def get_projects():
    return []

@router.post("", status_code=201)
def create_project(project: ProjectCreate):
    return {"message": "Project created successfully", "data": project.dict()}

@router.patch("/{project_id}")
def update_project(project_id: str, update_data: ProjectUpdate):
    return {"message": f"Project {project_id} updated successfully"}

@router.post("/{project_id}/members")
def add_project_members(project_id: str, members: ProjectMembersUpdate):
    return {"message": f"Members added to project {project_id} successfully"}

@router.delete("/{project_id}/members")
def remove_project_member(project_id: str, member: ProjectMembersUpdate):
    return {"message": f"Member removed from project {project_id} successfully"}
